# Proto Server - Guia de Instalação e Uso

## 📋 Visão Geral

O **Proto Server** é o componente responsável por manter os túneis privados do ecossistema DTunnel.  
Este repositório distribui:

- Binários oficiais `proto-server` (servidor principal) e `proxy-server` (bridge TCP).
- O script `proto`, que oferece um menu interativo para iniciar, parar e configurar o serviço via `systemd`.
- Um instalador automatizado que detecta arquitetura, baixa as versões desejadas e instala tudo em `/usr/local/bin`.

## ⚙️ Pré-requisitos

- Distribuição Linux com `systemd` (testado em Ubuntu/Debian/CentOS).
- Acesso root (`sudo`) para instalar binários e serviços.
- Ferramentas padrão: `curl`, `openssl`.
- Token de autenticação válido fornecido pela equipe DTunnel.

## 🚀 Instalação Rápida

Execute o comando abaixo (recomendado) para baixar a última versão, escolher o release desejado e instalar automaticamente:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/DTunnel0/DTProto-Server-Releases/main/install-server.sh)
```

### O que o instalador faz

- Detecta a arquitetura (`linux-amd64`, `linux-arm64`, etc.).
- Permite selecionar a versão dos binários `proto-server` e `proxy-server`.
- Move os executáveis para `/usr/local/bin` utilizando os nomes `proto-server` e `proxy-server`.
- Instala o gerenciador `proto` (script `proto-server.sh`) em `/usr/local/bin/proto`.
- Prepara o ambiente padrão em `/etc/proto-server` e `/var/lib/proto-server`.

## 📦 Instalação Manual (sem o wrapper `<(curl …)>`)

```bash
curl -fsSL https://raw.githubusercontent.com/DTunnel0/DTProto-Server-Releases/main/install-server.sh -o install-server.sh
chmod +x install-server.sh
sudo ./install-server.sh
```

Se preferir instalar manualmente sem o script, faça o download direto dos binários nas [releases](https://github.com/DTunnel0/DTProto-Server-Releases/releases), mova-os para `/usr/local/bin/`, garanta permissões de execução e configure o serviço conforme desejar.

## 🧰 Gerenciamento com `proto`

Após a instalação, utilize o comando abaixo (sempre como root) para abrir o menu interativo:

```bash
sudo proto
```

### Estrutura de diretórios

- Configurações: `/etc/proto-server/config.conf` e `/etc/proto-server/token`.
- Certificados TLS gerados automaticamente: `/var/lib/proto-server/cert.pem` e `key.pem`.
- Dados e arquivos auxiliares: `/var/lib/proto-server/credentials.json` e `stats.json`.
- Serviço systemd: `/etc/systemd/system/proto-server.service`.

## 🔁 Atualização

Para atualizar os binários, execute novamente o instalador (com `sudo`).  
Você pode selecionar a mesma versão ou escolher um release mais recente. O serviço será substituído mantendo configurações existentes.

## 🧹 Remoção

```bash
sudo systemctl stop proto-server
sudo systemctl disable proto-server
sudo rm -f /usr/local/bin/proto /usr/local/bin/proto-server /usr/local/bin/proxy-server
sudo rm -f /etc/systemd/system/proto-server.service
sudo rm -rf /etc/proto-server /var/lib/proto-server
sudo systemctl daemon-reload
```


## 📞 Suporte

- **Autor**: Glemison C. DuTra (@DuTra01)
- **GitHub**: https://github.com/DTunnel0/DTProto

---

**Built with ❤️ by the DTunnel team**
