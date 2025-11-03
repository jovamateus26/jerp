SHELL := /bin/bash

.PHONY: up down logs migrate help

up:
	docker compose --env-file .env up -d
	docker compose ps

down:
	docker compose down

logs:
	docker compose logs -f backend

site-%:
	./scripts/provision_site.sh $*

migrate:
	./scripts/migrate_all.sh

backup-%:
	./scripts/backup_site.sh $*

restore-%:
	./scripts/restore_site.sh $* "${DB_BACKUP}" "${FILES_BACKUP}"

help:
	@echo "Available targets: up, down, logs, site-<FQDN>, migrate, backup-<FQDN>, restore-<FQDN>"
	@echo "Use DB_BACKUP and FILES_BACKUP variables with restore-<FQDN>"
