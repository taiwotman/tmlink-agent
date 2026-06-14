COMPOSE = docker compose -f docker-compose.official.yml

.PHONY: start stop restart logs setup reset status

## Start all services
start:
	$(COMPOSE) up -d

## Stop all services (data preserved)
stop:
	$(COMPOSE) down

## Restart all services
restart:
	$(COMPOSE) down
	$(COMPOSE) up -d

## First-time setup (pulls images, builds, imports workflows)
setup:
	chmod +x agents_setup.sh
	./agents_setup.sh

## Show running containers and ports
status:
	docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAME|tmlink|n8n"

## Follow logs for all services
logs:
	$(COMPOSE) logs -f

## Follow logs for a specific service: make logs-n8n | make logs-tmlink
logs-n8n:
	$(COMPOSE) logs -f n8n

logs-tmlink:
	$(COMPOSE) logs -f tmlink

logs-ui:
	$(COMPOSE) logs -f agents-ui

## Full reset — WARNING: deletes all n8n workflow data and volumes
reset:
	$(COMPOSE) down -v
	./agents_setup.sh
