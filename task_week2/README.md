# Tuần 2 – Cluster RKE2 (1 master + 1 worker) + Longhorn trên EC2

```
bastion ──SSH / kubectl :6443──► rke2-master (RKE2 server: API server, etcd, scheduler + chạy pod)
                                      ▲ :9345 join (token)
                                 rke2-worker (RKE2 agent: kubelet + containerd, chỉ chạy pod)
         Longhorn: biến ổ đĩa của các node thành volume Kubernetes (PVC), có bản sao trên nhiều node
```

Phiên bản (kiểm tra 2026-11-25): RKE2 **v1.36.6+rke2r1** (kênh stable), Longhorn **v1.13.0** (cần Kubernetes ≥ 1.34).

## 1. Máy – Terraform

[`terraform/rke2`](terraform/rke2): 2 × c7i-flex.large (2 vCPU, 4 GB), Ubuntu 24.04, đĩa 30/40 GB,
hostname `rke2-master` / `rke2-worker`. Security group: mọi cổng giữa 2 node, SSH + 6443 chỉ từ bastion.

```bash
ssh-keygen -t ed25519 -f ~/.ssh/devops-rke2 -N ""
cd task_week2/terraform/rke2 && terraform init && terraform apply
terraform output            # IP private + lệnh ssh
```

## 2. RKE2 server trên master

```bash
$(terraform output -raw ssh_master)
curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_VERSION=v1.36.6+rke2r1 sh -   # cài, CHƯA chạy
sudo systemctl enable --now rke2-server                                          # chạy ngay + tự chạy khi boot
sudo journalctl -u rke2-server -f                                                # xem quá trình khởi động (2-3 phút)
```

| Đường dẫn trên master | Là gì |
|---|---|
| `/etc/rancher/rke2/config.yaml` | Cấu hình tùy chọn (tên giống cờ dòng lệnh). Master ở đây không cần |
| `/etc/rancher/rke2/rke2.yaml` | **kubeconfig** = quyền admin cluster (địa chỉ API + chứng chỉ) |
| `/var/lib/rancher/rke2/bin/` | `kubectl`, `crictl`, `ctr` đi kèm RKE2 (chưa có trong PATH) |
| `/var/lib/rancher/rke2/server/node-token` | Mật khẩu để node khác join |
| `/var/lib/rancher/rke2/server/manifests/` | Add-on RKE2 tự cài: Canal (mạng pod), CoreDNS, ingress-nginx, metrics-server |

```bash
echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin' >> ~/.bashrc && source ~/.bashrc
mkdir -p ~/.kube && sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config && sudo chown ubuntu: ~/.kube/config
kubectl get nodes -o wide     # rke2-master  Ready  control-plane,etcd
kubectl get pods -A           # pod hệ thống: Running hoặc Completed
```

Master **không bị taint**: vẫn chạy pod thường, nên Longhorn có 2 node để đặt bản sao.
(Production: 3 master có `node-taint: CriticalAddonsOnly=true:NoExecute`, app chỉ chạy trên worker.)

## 3. RKE2 agent trên worker (join cluster)

Worker cần biết **master ở đâu** + **token** → ghi vào `/etc/rancher/rke2/config.yaml` của worker. Làm từ bastion,
token đi thẳng từ master sang worker qua SSH (không hiện ra màn hình, không lưu file trên bastion):

```bash
cd task_week2/terraform/rke2
MASTER=$(terraform output -raw master_private_ip); WORKER=$(terraform output -raw worker_private_ip)
TOKEN=$(ssh -i ~/.ssh/devops-rke2 ubuntu@$MASTER sudo cat /var/lib/rancher/rke2/server/node-token)
printf 'server: https://%s:9345\ntoken: %s\n' "$MASTER" "$TOKEN" \
  | ssh -i ~/.ssh/devops-rke2 ubuntu@$WORKER 'sudo install -D -m 600 /dev/stdin /etc/rancher/rke2/config.yaml'
unset TOKEN
```

Trên worker:
```bash
curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_VERSION=v1.36.6+rke2r1 INSTALL_RKE2_TYPE=agent sh -
sudo systemctl enable --now rke2-agent
sudo journalctl -u rke2-agent -f
```

Trên master:
```bash
kubectl get nodes -o wide            # rke2-master + rke2-worker đều Ready
kubectl label node rke2-worker node-role.kubernetes.io/worker=true   # chỉ để cột ROLES hiện "worker"
kubectl get pods -A -o wide          # canal, kube-proxy chạy trên CẢ 2 node
```

## 4. `kubectl` từ bastion

Bastion cần: (1) chương trình `kubectl` (cùng phiên bản Kubernetes của cluster), (2) kubeconfig của master
với địa chỉ `127.0.0.1` đổi thành IP private của master. Security group đã mở 6443 cho bastion.

```bash
cd /tmp
curl -LO https://dl.k8s.io/release/v1.36.6/bin/linux/amd64/kubectl
curl -LO https://dl.k8s.io/release/v1.36.6/bin/linux/amd64/kubectl.sha256
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check          # phải in: kubectl: OK
sudo install -m 755 kubectl /usr/local/bin/kubectl && rm kubectl kubectl.sha256
kubectl version --client

cd ~/devops-tma/task_week2/terraform/rke2
MASTER=$(terraform output -raw master_private_ip)
mkdir -p ~/.kube
ssh -i ~/.ssh/devops-rke2 ubuntu@$MASTER 'sudo cat /etc/rancher/rke2/rke2.yaml' \
  | sed "s/127.0.0.1/$MASTER/" > ~/.kube/config
chmod 600 ~/.kube/config
kubectl get nodes -o wide
```

kubeconfig = quyền **admin** cluster: chỉ để ở `~/.kube/config` (ngoài repo), quyền 600, không commit.
