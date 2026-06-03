# secrets/

Fonte única de secrets do homed. Cada ficheiro `<service>.env` é encriptado **in-place** com sops+age (o ficheiro tem sempre o mesmo nome — encriptado ou plaintext — e os composes apontam sempre para `<service>.env`).

## Ficheiros

| Ficheiro | Serviço | Conteúdo |
|---|---|---|
| `h-auth.env` | Authelia | JWT secret, session secret, storage encryption key |

(adicionar entradas à medida que novos secrets são criados)

## Operação

```bash
task up                 # decifra in-place todos os secrets/*.env (600) e arranca o stack
task decrypt            # só decifra (idempotente — ignora os já em plaintext)
task lock               # re-encripta in-place (correr antes de commit)
task edit NAME=h-auth   # editar em-place (sops abre $EDITOR, re-encripta on save)
task rotate             # re-encriptar tudo com a lista de recipients atual de .sops.yaml
```

## Adicionar um secret novo

```bash
# 1. criar plaintext (NUNCA commitar este passo intermédio)
cat > secrets/h-foo.env <<EOF
FOO_TOKEN=...
EOF

# 2. encriptar in-place (mesmo nome de ficheiro, agora encriptado)
task encrypt NAME=h-foo
#   internamente: sops -e -i --input-type dotenv --output-type dotenv secrets/h-foo.env

# 3. referenciar no compose do serviço (3 ups, post-flatten)
#    env_file: ../../../secrets/h-foo.env
```

## Backup da chave age

Localização runtime: `~/.config/sops/age/keys.txt` (perms 600).

Backup OBRIGATÓRIO em 3 sítios:
- 1Password (vault homed)
- USB encriptada com passphrase
- Em produção: no próprio Beelink, protegida por LUKS
