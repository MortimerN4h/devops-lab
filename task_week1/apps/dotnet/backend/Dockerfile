# ---- Stage 1 "build": the .NET SDK (compiler + NuGet, ~800 MB) ----
FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS build
WORKDIR /src
# Project file first: download NuGet packages in their own layer (cached until Notes.csproj changes)
COPY Notes.csproj .
RUN dotnet restore
COPY . .
# publish = compile in Release mode + copy everything needed to run into /out (DLLs, config)
RUN dotnet publish -c Release --no-restore -o /out

# ---- Stage 2: only the ASP.NET Core RUNTIME (runs .NET apps, cannot compile them) ----
FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine
WORKDIR /app
COPY --from=build /out .
# The official image already has a non-root user; APP_UID is its number (1654)
USER $APP_UID
# The image sets ASPNETCORE_HTTP_PORTS=8080: Kestrel (the built-in web server) listens on 8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "Notes.dll"]
