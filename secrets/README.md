# secrets/

Fonte única de secrets do homed. Cada ficheiro `<service>.env.sops` é encriptado com sops+age.

## Ficheiros

| Ficheiro | Serviço | Conteúdo |
|---|---|---|
| `h-auth.env.sops` | Authelia | JWT secret, session secret, storage encryption key |

(adicionar entradas à medida que novos secrets são criados)

## Operação

```bash
task up          # decifra todos os *.env.sops → *.env (600) e arranca o stack
task edit NAME=h-auth   # editar em-place (sops abre $EDITOR, re-encripta on save)
task rotate      # re-encriptar tudo com a lista de recipients atual de .sops.yaml
task clean       # remover os *.env decifrados
```

## Adicionar um secret novo

```bash
# 1. criar plaintext (NUNCA commitar este passo intermédio)
cat > secrets/h-foo.env <<EOF
FOO_TOKEN=...
EOF

# 2. encriptar e remover plaintext
sops -e secrets/h-foo.env > secrets/h-foo.env.sops
rm secrets/h-foo.env

# 3. referenciar no compose do serviço
#    env_file: ../../../../secrets/h-foo.env
```

## Backup da chave age

Localização runtime: `~/.config/sops/age/keys.txt` (perms 600).

Backup OBRIGATÓRIO em 3 sítios:
- 1Password (vault homed)
- USB encriptada com passphrase
- Em produção: no próprio Beelink, protegida por LUKS
