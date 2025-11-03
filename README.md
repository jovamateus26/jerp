# Jerp SaaS Platform Runbook

## Arquitetura
- **Imagem custom**: construída a partir do `frappe_docker`, incorpora o ERPNext e demais apps listados no `apps.json`.
- **Stack de produção**: definida no `compose.yml` com MariaDB, três instâncias Redis (queue/cache/socketio), backend, scheduler, três workers (default/long/short), websocket e frontend (Nginx) servindo na porta interna 8080.
- **Multitenancy**: cada cliente opera em um site dedicado, com banco isolado e assets compartilhados via volumes persistentes.
- **Orquestração**: Portainer gerencia o deploy da stack; o Nginx Proxy Manager (NPM) publica cada domínio de cliente apontando para `frontend:8080` com suporte a WebSockets e SSL Let’s Encrypt.

## Pré-requisitos
1. Host ou cluster com Docker e Portainer instalados.
2. Rede Docker externa compartilhada com o NPM (ex.: `proxy`).
3. DNS dos clientes apontando para o IP público do host.
4. Registry privado acessível (URL, credenciais, permissões de push/pull).
5. Segredos configurados no GitHub (`REGISTRY_URL`, `REGISTRY_USER`, `REGISTRY_PASS`, opcional `PORTAINER_WEBHOOK_URL`).
6. Variáveis do repositório para controlar branch e metadados (`REGISTRY_IMAGE_NAME`, `REGISTRY_IMAGE_TAG`, `FRAPPE_BRANCH`).

## Configuração de CI/CD
1. Crie os **Secrets** no GitHub (`Settings` → `Secrets and variables` → `Actions`):
   - `REGISTRY_URL`: endpoint do registry (ex.: `registry.example.com`).
   - `REGISTRY_USER`: usuário com permissão de push.
   - `REGISTRY_PASS`: senha ou token do usuário.
   - `PORTAINER_WEBHOOK_URL` (opcional): URL para atualizar a stack automaticamente.
2. Defina **Variables** (se preferir sobrepor os defaults do workflow):
   - `REGISTRY_IMAGE_NAME`: nome da imagem (ex.: `erpnext-custom`).
   - `REGISTRY_IMAGE_TAG`: tag canônica de produção (ex.: `15-prod`).
   - `FRAPPE_BRANCH`: branch do Frappe/ERPNext (ex.: `version-15`).
3. Ao realizar push na branch `main`, o GitHub Actions executará o pipeline `Build custom ERPNext image`.

### O que o pipeline faz
1. Faz checkout deste repositório e do `frappe_docker` oficial.
2. Prepara o contexto de build levando o `apps.json`.
3. Realiza login no registry privado.
4. Compila a imagem custom embutindo os apps informados.
5. Publica duas tags:
   - **Imutável**: `${REGISTRY_URL}/${IMAGE_NAME}:${SHORT_SHA}` para auditoria/rollback.
   - **Produção**: `${REGISTRY_URL}/${IMAGE_NAME}:${REGISTRY_IMAGE_TAG}` para Portainer.
6. (Opcional) Dispara webhook do Portainer para atualizar a stack automaticamente.

## Deploy da stack no Portainer
1. Baixe o `compose.yml` para o Portainer e selecione a rede externa compartilhada `proxy`.
2. Crie um arquivo `.env` fora do versionamento (ou use o gerenciador de variáveis do Portainer) preenchendo os valores de `.env.example`.
3. Garanta volumes persistentes (`db-data`, `frappe-sites`, `frappe-assets`, `frappe-logs`) e execute o stack deploy.
4. Nenhuma porta é publicada diretamente; o acesso externo ocorre via NPM.

## Provisionamento de um novo cliente
1. No host (ou via Portainer exec), execute `make site-cliente.exemplo.com`.
2. O script `provision_site.sh` deve:
   - Ler `MARIADB_ROOT_PASSWORD` e `FRAPPE_ADMIN_PASSWORD` do ambiente.
   - Criar o site, instalar ERPNext e (quando disponível) o app NFS-e PR.
   - Instruir a criação do Proxy Host no NPM.
3. No NPM, crie um Proxy Host apontando o domínio do cliente para `frontend:8080`, habilite WebSockets e configure SSL Let’s Encrypt (HTTP challenge ou DNS de acordo com sua infraestrutura).

## Ciclo de release
1. **Build**: commit na `main` dispara o pipeline que gera e publica as novas tags.
2. **Atualização da stack**: Portainer aplica a nova tag (manualmente ou via webhook).
3. **Migração**: após os containers atualizarem, execute `make migrate`.
   - Script `migrate_all.sh` deve fazer backup, aplicar migrações, limpar caches e reconstruir assets para todos os sites.
4. **Smoke tests** pós-release:
   - Login no Desk com usuário de validação.
   - Testar criação/edição de documentos, notificações em tempo real, fila de jobs (monitorar `worker`/`scheduler`).

## Rollback
1. Identifique a tag imutável anterior (ex.: obtida via histórico do registry ou logs do pipeline).
2. Atualize o stack no Portainer apontando para a tag anterior.
3. Execute novamente `make migrate` para garantir consistência do schema.
4. Realize smoke tests e confirme a estabilidade.
5. Se necessário, aplique `restore_site.sh` usando os backups pré-release.

## Backups & Restore
- **Frequência**: diário para banco e arquivos; mantenha retenção mínima alinhada à LGPD e requisitos de negócio.
- **Localização**: armazene cópias off-site (S3, storage seguro) com criptografia.
- **Procedimento**:
  - `make backup-cliente.exemplo.com` aciona `backup_site.sh` (deve registrar caminho dos artefatos).
  - `make restore-cliente.exemplo.com DB_BACKUP=/caminho/sql.gz FILES_BACKUP=/caminho/files.tar.gz` usa `restore_site.sh` para recuperar dados e rodar migrações.
- **Teste periódico**: valide restores em ambiente de staging ao menos trimestralmente.

## Segurança & LGPD
- Sites segregados por cliente garantem isolamento lógico.
- Utilize credenciais distintas por ambiente (staging vs produção) e armazene-as apenas em Secrets/variáveis seguras.
- Nunca versionar `.env` reais; apenas `.env.example` com placeholders.
- Habilite SSL em todos os domínios e mantenha WebSockets ativos para funcionalidades em tempo real.
- Considere hardening do host (firewall, atualizações automáticas, monitoramento de acesso) e políticas de retenção de logs conforme LGPD.

## Observabilidade
- Consulte os logs com `make logs` ou diretamente no Portainer.
- Monitore a saúde do scheduler e workers (consumo de CPU/RAM/IO, filas Redis).
- Avalie integrar métricas e alertas (Prometheus, Grafana, Sentry) para filas, erros e tempo de resposta.

## Adição do app NFS-e PR (futuro)
1. Inclua uma nova entrada no `apps.json`, por exemplo:
   ```json
   {
     "name": "nfse-pr",
     "repository": "https://github.com/sua-org/nfse-pr",
     "branch": "main"
   }
   ```
2. Atualize (se necessário) as variáveis `FRAPPE_BRANCH` ou tags de compatibilidade.
3. Execute commit/push para disparar o pipeline, gerar nova imagem e atualizar a stack.
4. No provisionamento de cada site existente, instale o app adicional (ajuste o `provision_site.sh`).
5. Documente certificados (A1/A3), agendamentos assíncronos e particularidades de cada prefeitura/UF.

## Padrões de versionamento
- Utilize duas tags por release: `:<SHORT_SHA>` para auditoria e `:15-prod` (ou similar) como referência principal.
- Mantenha matriz de compatibilidade (ERPNext × apps customizados) e valide breaking changes em staging.

## Ambiente de staging
- Mantenha um stack idêntico apontando para a mesma versão do compose.
- Provisione sites de homologação para validar releases, backups e restores antes de produção.

## Automação opcional
- Configure webhook do Portainer (secret `PORTAINER_WEBHOOK_URL`) para atualizar a stack automaticamente após o push da imagem.
- Considere automação de DNS e criação de Proxy Hosts via APIs do NPM ou Cloudflare para reduzir ações manuais.

## Operação esperada
1. **Build**: push na `main` → pipeline lê `apps.json` → imagem custom compilada com tags imutável e de produção.
2. **Deploy/Atualização**: Portainer atualiza a stack com a tag de produção → executar `make migrate` → validar.
3. **Provisionamento de cliente**: rodar `make site-<FQDN>` → instalar apps → configurar Proxy Host no NPM.
4. **Backup/Restore**: agendar backups diários → armazenar off-site → testar restore regularmente.
5. **Rollback**: manter tag anterior → reverter stack se necessário → reexecutar migração/validação.

## Próximos passos para implementação dos scripts
- Completar os scripts em `scripts/` para executarem bench commands dentro do container `backend` e encapsularem provisionamento, migrações, backups e restore.
- Garantir que todos os scripts falhem em caso de erro (`set -euo pipefail` já configurado).
- Integrar logs e notificações conforme políticas internas.

