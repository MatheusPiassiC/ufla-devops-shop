# Atividade 03 — Deploy, systemd, backup e proxy TLS

DevOps na Prática — DCC/UFLA

## 1. Deploy em uma máquina limpa

Execute o script a partir da raiz do repositório:

```bash
sudo ./scripts/deploy.sh
```

O script cria o usuário `ufla-shop`, instala a aplicação em `/opt/ufla-shop`,
cria o ambiente virtual, instala as dependências, configura as units do
systemd, gera o certificado TLS e habilita o Nginx e o timer de backup.

As últimas linhas das duas execuções foram:

```text
==> Validando configuração do Nginx...
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
Synchronizing state of nginx.service with SysV service script with /usr/lib/systemd/systemd-sysv-install.
Executing: /usr/lib/systemd/systemd-sysv-install enable nginx
==> Habilitando backup diário...
==> Executando healthcheck...
Healthcheck OK.
```

O mesmo resultado foi obtido na primeira e na segunda execução consecutiva,
sem duplicar usuário, certificado, link do Nginx ou unit systemd. O arquivo
`/etc/ufla-shop.env` também foi preservado na segunda execução.

## 2. Evidência do Restart automático

O PID principal foi obtido e encerrado com:

```bash
PID=$(sudo systemctl show -p MainPID --value ufla-shop)
echo "PID antes: $PID"
sudo kill -9 "$PID"
sleep 5
sudo systemctl status ufla-shop --no-pager
```

Saída obtida:

```text
PID antes: 31938
● ufla-shop.service - ufla-devops-shop API
     Loaded: loaded (/etc/systemd/system/ufla-shop.service; enabled; preset: enabled)
     Active: active (running) since Sat 2026-09-26 17:05:32 -03; 9s ago
   Main PID: 33182 (uvicorn)
      Tasks: 1 (limit: 18656)
     Memory: 41.9M (peak: 42.8M)
        CPU: 432ms
     CGroup: /system.slice/ufla-shop.service
             └─33182 /opt/ufla-shop/.venv/bin/python3 /opt/ufla-shop/.venv/bin/uvicorn app:api --host 127.0.0.1 --port 8000

set 26 17:05:30 pop-os systemd[1]: ufla-shop.service: Failed with result 'signal'.
set 26 17:05:32 pop-os systemd[1]: ufla-shop.service: Scheduled restart job, restart counter is at 1.
set 26 17:05:32 pop-os systemd[1]: Started ufla-shop.service - ufla-devops-shop API.
```

O novo PID `33182` e o estado `active (running)` comprovam o reinício
automático após o `kill -9`.

## 3. Evidência do proxy reverso TLS

Comandos executados:

```bash
curl -kI https://localhost
curl -I http://localhost
```

Saída obtida:

```text
HTTP/1.1 405 Method Not Allowed
Server: nginx/1.24.0 (Ubuntu)
Date: Sat, 26 Sep 2026 20:05:55 GMT
Content-Type: application/json
Content-Length: 31
Connection: keep-alive
allow: GET
```

```text
HTTP/1.1 301 Moved Permanently
Server: nginx/1.24.0 (Ubuntu)
Date: Sat, 26 Sep 2026 20:06:00 GMT
Content-Type: text/html
Content-Length: 178
Connection: keep-alive
Location: https://localhost/
```

O redirect HTTP `301` foi comprovado. O HTTPS retornou `405` porque `curl -I`
envia `HEAD` e a rota `/` original aceita somente `GET`; portanto, essa saída
ainda não é a evidência final exigida de `200` pelo enunciado. Após executar
novamente o deploy com a configuração Nginx atualizada, capture e substitua o
primeiro bloco pelo retorno `HTTP/1.1 200 OK`.

## 4. Evidência da rotação de backups

O serviço foi executado três vezes, em minutos diferentes:

```bash
sudo systemctl start ufla-shop-backup.service
sudo systemctl start ufla-shop-backup.service
sudo systemctl start ufla-shop-backup.service
sudo ls -la /var/backups/ufla-shop
```

Saída obtida:

```text
total 20
drwxr-x--- 2 postgres postgres 4096 set 26 17:12 .
drwxr-xr-x 3 root     root     4096 set 26 16:47 ..
-rw-r--r-- 1 postgres postgres 1621 set 26 17:10 loja-2026-09-26-1710.sql.gz
-rw-r--r-- 1 postgres postgres 1622 set 26 17:11 loja-2026-09-26-1711.sql.gz
-rw-r--r-- 1 postgres postgres 1620 set 26 17:12 loja-2026-09-26-1712.sql.gz
```

Os três dumps foram gerados com sucesso, pertencem ao usuário `postgres` e
possuem tamanhos válidos.

## 5. Prova da idempotência

Comandos usados para salvar e comparar as duas execuções:

```bash
sudo ./scripts/deploy.sh 2>&1 | tee /tmp/deploy-1.log
sudo ./scripts/deploy.sh 2>&1 | tee /tmp/deploy-2.log
tail -n 12 /tmp/deploy-1.log
tail -n 12 /tmp/deploy-2.log
```

Últimas linhas da primeira execução:

```text
Executing: /usr/lib/systemd/systemd-sysv-install enable redis-server
==> Iniciando aplicação...
==> Configurando Nginx...
==> Gerando certificado TLS...
==> Validando configuração do Nginx...
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
Synchronizing state of nginx.service with SysV service script with /usr/lib/systemd/systemd-sysv-install.
Executing: /usr/lib/systemd/systemd-sysv-install enable nginx
==> Habilitando backup diário...
==> Executando healthcheck...
Healthcheck OK.
```

Últimas linhas da segunda execução:

```text
Executing: /usr/lib/systemd/systemd-sysv-install enable redis-server
==> Iniciando aplicação...
==> Configurando Nginx...
==> Gerando certificado TLS...
==> Validando configuração do Nginx...
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
Synchronizing state of nginx.service with SysV service script with /usr/lib/systemd/systemd-sysv-install.
Executing: /usr/lib/systemd/systemd-sysv-install enable nginx
==> Habilitando backup diário...
==> Executando healthcheck...
Healthcheck OK.
```
