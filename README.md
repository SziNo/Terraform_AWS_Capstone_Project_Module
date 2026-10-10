# Skálázható AWS infrastruktúra Terraform modulokkal

Egy VPC-re épülő AWS infrastruktúra, modulokra bontva. Minden skálázható rész (subnetek, EC2 gépek, bastion hostok, target group regisztrációk) `for_each`-csel, név szerint kulcsolt mapeken jön létre, `count` sehol nincs a projektben. Erőforrás hozzáadásához vagy elvételéhez csak a `terraform.tfvars`-t kell módosítani, a kódot nem, és a meglévő erőforrások érintetlenek maradnak.

## Architektúra

```
┌──────────────────────────────── VPC (10.0.0.0/16) ────────────────────────────────┐
│                                                                                    │
│   Public subnetek (public-a / public-b / public-c)                                  │
│   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐                           │
│   │  bastion-1   │   │  bastion-2   │   │  bastion-3   │      ┌──────────────┐     │
│   └──────────────┘   └──────────────┘   └──────────────┘      │     ALB      │     │
│          NAT Gateway (public-a)                               └──────┬───────┘     │
│                │                                                     │ :80         │
│   Private subnetek (private-a / private-b / private-c)               ▼             │
│   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐                           │
│   │ private-a-1  │   │ private-b-1  │   │ private-c-1  │   (nginx minden gépen)    │
│   │ private-a-2  │   │              │   │              │                           │
│   └──────────────┘   └──────────────┘   └──────────────┘                           │
│                                                                                    │
└──────────────── Internet Gateway ──────────────────────────────────────────────────┘
```

Forgalmi utak:

- **SSH:** saját gép → bastion (22, csak az `allowed_ssh_cidr`-ről) → privát EC2 (22, csak a bastion SG-ből)
- **HTTP:** internet → ALB (80) → privát EC2 (80, csak az ALB SG-ből)
- **Kimenő forgalom:** privát EC2 → NAT Gateway → internet (pl. `dnf install`)

## Projektstruktúra

```
.
├── versions.tf                 # Terraform és provider verziók, S3 backend
├── providers.tf                # AWS provider, default_tags
├── variables.tf                # root bemenetek
├── locals.tf                   # segédértékek az outputokhoz
├── data.tf                     # Amazon Linux 2023 AMI lekérdezés
├── main.tf                     # key pair, modulhívások, összekötő SG szabály
├── outputs.tf                  # formázott outputok, SSH parancsok
├── terraform.tfvars.example    # minta a saját terraform.tfvars-hoz
├── scripts/
│   ├── ec2-userdata.sh         # nginx telepítés a privát gépekre
│   └── teardown.sh             # destroy + a state takarítása a bucketből
└── modules/
    ├── vpc/                    # VPC, subnetek, IGW, NAT, route táblák
    ├── ec2-instance/           # privát EC2 gépek és a security groupjuk
    ├── bastion/                # bastion hostok és a security groupjuk
    └── alb/                    # Application Load Balancer, target group, listener
```

## Modulok

### `vpc`

Létrehozza a VPC-t, a subneteket (a `type` mező alapján public vagy private), az Internet Gatewayt, a NAT Gatewayt (Elastic IP-vel), a public és private route táblát, valamint a subnetek associationjeit.

| Bemenet      | Leírás                                              |
| ------------ | --------------------------------------------------- |
| `vpc_config` | CIDR, név, és a NAT Gateway subnetje (`nat_subnet`) |
| `subnets`    | subnetek listája: név, CIDR, AZ, típus              |

| Output                                    | Leírás                             |
| ----------------------------------------- | ---------------------------------- |
| `vpc_id`, `vpc_cidr`                      | a VPC azonosítója és címtartománya |
| `public_subnet_ids`, `private_subnet_ids` | subnet név → ID map                |
| `nat_public_ip`                           | a privát gépek kimenő IP-je        |

### `ec2-instance`

A privát subnetekben létrehozza a gépeket a subnetenkénti darabszám alapján, és a gépek security groupját (SSH a bastion SG-ből, minden kifelé).

| Bemenet                                              | Leírás                       |
| ---------------------------------------------------- | ---------------------------- |
| `ec2_config`                                         | subnet név → gépszám         |
| `subnet_ids`, `vpc_id`                               | a VPC modulból               |
| `ami_id`, `instance_type`, `key_name`, `name_prefix` | a rootból                    |
| `user_data`                                          | opcionális script a gépeknek |
| `bastion_security_group_id`                          | a bastion modulból           |

| Output                        | Leírás                                     |
| ----------------------------- | ------------------------------------------ |
| `instance_ids`, `private_ips` | gépnév → ID / privát IP                    |
| `security_group_id`           | hogy a root szabályt köthessen hozzá (ALB) |

### `bastion`

A public subnetekben létrehozza a listában megadott bastion hostokat és a security groupjukat.

| Bemenet                                              | Leírás                              |
| ---------------------------------------------------- | ----------------------------------- |
| `bastion_config`                                     | bastionok listája: név, subnet      |
| `subnet_ids`, `vpc_id`, `vpc_cidr`                   | a VPC modulból                      |
| `ami_id`, `instance_type`, `key_name`, `name_prefix` | a rootból                           |
| `allowed_ssh_cidr`                                   | ahonnan SSH-zni lehet a bastionokra |

| Output                       | Leírás                         |
| ---------------------------- | ------------------------------ |
| `public_ips`, `instance_ids` | bastion név → publikus IP / ID |
| `security_group_id`          | az EC2 modul SSH szabályához   |

### `alb`

Application Load Balancer a public subnetekben, target group health checkkel, a gépek regisztrációja, HTTP listener, és az ALB security groupja.

| Bemenet                            | Leírás                               |
| ---------------------------------- | ------------------------------------ |
| `subnet_ids`, `vpc_id`, `vpc_cidr` | a VPC modulból                       |
| `target_instance_ids`              | az EC2 modul `instance_ids` outputja |
| `name_prefix`                      | a rootból                            |
| `health_check_path`                | opcionális, alapértéke `/health`     |

| Output              | Leírás                       |
| ------------------- | ---------------------------- |
| `dns_name`          | az ALB publikus címe         |
| `security_group_id` | a root összekötő szabályához |

Az ALB-t a kész projekthez adtuk hozzá úgy, hogy a `vpc`, `ec2-instance` és `bastion` modul egyetlen fájljához sem kellett nyúlni: csak egy új modul, egy új modulhívás, egy összekötő SG szabály és egy új output került a rootba.

## Skálázhatóság

A bemenetek listák vagy mapek, amiket a modulok név szerint kulcsolt mapekké alakítanak (list-to-map minta), és ezeken megy a `for_each`. A resource címek így nevet viselnek index helyett, pl. `module.vpc.aws_subnet.private["private-a"]`, `module.ec2.aws_instance.this["private-a-2"]`.

Az EC2 modul a subnetenkénti darabszámból gépenkénti mapet készít (`merge` + beágyazott `for`):

```
{ "private-a" = 2, "private-b" = 1 }
  => { "private-a-1" = "private-a", "private-a-2" = "private-a", "private-b-1" = "private-b" }
```

Példák, amikhez csak a `terraform.tfvars`-t kell módosítani:

- **Új subnet:** egy új sor a `subnets` listában → a plan csak a subnetet és az associationjét hozza létre.
- **Több gép egy subnetben:** `"private-a" = 3` → egy új gép jön létre (`private-a-3`), és automatikusan bekerül az ALB target groupjába.
- **Gép elvétele:** a darabszám csökkentésekor mindig az utolsó sorszámú gép törlődik, a többi érintetlen.
- **Új bastion:** egy új elem a `bastion_config` listában.

Hibás bemenetet a változók validációi már a plan elején jeleznek: ismeretlen subnet típus, nem létező vagy nem public NAT subnet, ismeretlen subnet az `ec2_config`-ban vagy a `bastion_config`-ban, duplikált bastion név, negatív vagy tört gépszám, egynél kevesebb ALB subnet, nem engedélyezett instance típus.

## Tervezési döntések

- **A key pair a rootban van**, a feladat leírásával ellentétben (az EC2 modul helyett). Az EC2 gépek és a bastionok is használják, ezért a legközelebbi közös szülőbe került. Így mindkét modul egyenrangúan kapja a kulcs nevét, és nem kell az egyik modulnak a másiknak továbbadnia. A root ugyanígy birtokolja a közös AMI data source-t is.
- **A security group szabályok külön resource-ok** (`aws_vpc_security_group_ingress_rule` / `egress_rule`), nem inline blokkok. Így más modulok vagy a root ütközés nélkül adhatnak szabályt egy SG-hez, ahogy az ALB → EC2 szabálynál történik.
- **Az ALB → EC2 összekötő szabály a rootban van**, mert két modul SG-jét köti össze. Így egyik modulnak sem kell tudnia a másikról.
- **Legkisebb jogosultság (least privilege):** a bastion kifelé csak SSH-t indíthat a VPC-n belülre, internet-hozzáférése nincs. Az ALB kifelé csak HTTP-t a VPC-be. A bastiont nem frissítjük helyben; ha új csomag vagy javítás kell, friss AMI-ból újraépül (immutable infrastructure).
- **A NAT Gateway helye explicit** (`nat_subnet`), validációval. Pozíció alapú választásnál (pl. az első public subnet) egy új subnet felvétele a NAT cseréjét okozhatná.
- **A `private_subnet_ids` output a route table associationöktől függ** (`depends_on`), így a privát gépek csak akkor indulnak, amikor a NAT route már él, és a user data `dnf install` parancsa nem hasal el boot közben.
- **IMDSv2 kötelező** minden gépen (`http_tokens = "required"`).
- **`default_tags` a providerben:** az `Environment`, `Project` és `ManagedBy` tag minden erőforrásra automatikusan rákerül, a modulokban csak a `Name` tag szerepel.
- **Csak `t2.micro`** engedélyezett (root szintű validáció), a free tier miatt. A validáció a rootban van, nem a modulban, mert ez a fiók korlátja, nem a modulé.
- **Remote state S3-ban, `use_lockfile`-lal.** A feladat S3 + DynamoDB-t említ; a `use_lockfile` az újabb, S3-natív locking, ami a DynamoDB-s megoldást váltja. A bucket tudatosan **verziózás nélküli**: egyszerűbb a takarítás, cserébe egy véletlenül törölt vagy felülírt state nem állítható vissza.
- **Egyetlen NAT Gateway** költségkímélésből. Ha annak az AZ-ja kiesik, egyik privát subnet sem éri el az internetet (single point of failure).
- **Az AMI `most_recent = true`**: ha az Amazon új AMI-t ad ki, a következő plan a gépek cseréjét mutatja. Mivel a környezet minden alkalommal felépül és lebomlik, ez itt nem okoz gondot. A név filter (`al2023-ami-2023.*`) kizárja a minimal image-eket.

## Előfeltételek

- Terraform >= 1.16, AWS CLI beállított hitelesítéssel, régió: `eu-west-1`
- `ssh-agent` (az SSH ugráshoz), `jq` (opcionális, a JSON outputokhoz)

## Telepítés lépésről lépésre

1. **SSH kulcspár generálása** (a privát kulcs a gépeden marad, csak a publikus kerül az AWS-be):

   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/capstone-module-key -C "capstone-module"
   cat ~/.ssh/capstone-module-key.pub
   ```

2. **A `terraform.tfvars` elkészítése** a minta alapján. A saját publikus IP-d: `curl -s https://checkip.amazonaws.com`, a `allowed_ssh_cidr` ennek `/32`-es változata. A `key_pair.public_key` a `.pub` fájl tartalma.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

3. **A state bucket létrehozása** (egyszer, verziózás nélkül):

   ```bash
   aws s3 mb s3://szino-terraform-state --region eu-west-1
   ```

4. **A backend bekapcsolása:** a `versions.tf`-ben vedd le a kommentet a `backend "s3"` blokkról, majd:

   ```bash
   terraform init
   ```

   Mivel még nincs lokális state, nincs mit migrálni, a sima `init` elég.

5. **Ellenőrzés:**

   ```bash
   terraform fmt -recursive
   terraform validate
   terraform plan
   ```

   A plan az alapértékekkel: `Plan: 43 to add, 0 to change, 0 to destroy.` Modulonkénti bontás:

   ```bash
   terraform plan -no-color | grep "will be created" | grep -oE "module\.[a-z0-9_-]+" | sort | uniq -c
   ```

6. **Apply:**

   ```bash
   terraform apply
   ```

## Tesztelés

### 1. Outputok

```bash
terraform output
terraform output -json ssh_bastions | jq -r '."bastion-1"'
```

### 2. SSH a bastionra

```bash
ssh -i ~/.ssh/capstone-module-key ec2-user@<bastion-public-ip>
```

A kész parancsok a `ssh_bastions` outputban vannak.

### 3. SSH a privát gépekre a bastionon keresztül

A `ssh -J` (ProxyJump) egy lépésben ugrik át a bastionon. A privát kulcs végig a saját gépeden marad, a bastionra nem kerül semmi, ezért ez biztonságosabb, mint a kulcs átmásolása vagy az agent forwarding. A `-J` a jump hostnál nem használja a `-i` kapcsolót, ezért a kulcsot előbb be kell tölteni az agentbe:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/capstone-module-key
ssh -J ec2-user@<bastion-public-ip> ec2-user@<private-ip>
```

A kész parancsok a `ssh_ec2_instances` outputban vannak.

### 4. NAT és user data (a privát gépen)

```bash
systemctl status nginx                   # fut-e a user data által telepített nginx
curl -s localhost                        # "Hello from i-..."
curl -s https://checkip.amazonaws.com    # egyeznie kell a nat_public_ip outputtal
```

Ha az nginx fut, a `dnf install` sikeres volt, vagyis a NAT, a private route tábla és az output `depends_on`-ja is jól működik.

### 5. ALB

A target group health checkje kb. egy perc után jelöli healthy-nek a gépeket.

```bash
ALB_URL=$(terraform output -raw alb_url)
for i in $(seq 1 6); do curl -s "$ALB_URL"; echo; done   # különböző instance ID-k
curl -s "$ALB_URL/health"                                # OK
```

### 6. Negatív tesztek

- **A bastionról nincs internet** (csak SSH a VPC-n belül): a bastionon a `curl -m 5 https://checkip.amazonaws.com` időtúllépéssel elhasal.
- **A privát gépek kívülről nem érhetők el**, nincs publikus IP-jük; SSH csak a bastionon keresztül megy.
- **A gépek HTTP-n közvetlenül nem érhetők el**, a 80-as port csak az ALB SG-ből nyitott.

### 7. Skálázhatóság

Módosítsd a `terraform.tfvars`-ban a `"private-a"` értékét 3-ra, és futtass `terraform plan`-t: csak egy új gép és egy új target group attachment jelenik meg, minden más változatlan. Utána állítsd vissza.

## Lebontás

```bash
chmod +x scripts/teardown.sh    # egyszer
./scripts/teardown.sh
```

A script:

1. a projekt gyökerébe lép, bárhonnan is indítod (így nem futhat véletlenül egy üres mappában, ami state nélkül hagyná a futó erőforrásokat)
2. `terraform destroy -auto-approve`
3. törli a projekt state-jét a bucketből (`capstone-module/` prefix)
4. a bucketet csak akkor törli, ha utána üres maradt, így más projektek state-je nem vész el

Ha a `destroy` hibával áll meg, a script is megáll (`set -euo pipefail`), és a state megmarad.

## Költségek

A NAT Gateway és az ALB óradíjas, és minden publikus IPv4 cím is (a bastionoké és a NAT Elastic IP-je is), akkor is, ha használatban van. A tesztek után érdemes azonnal lebontani a környezetet.

## Továbbfejlesztési lehetőségek

- **Bastion helyett SSM Session Manager vagy EC2 Instance Connect Endpoint:** publikus IP és nyitott 22-es port nélkül ad hozzáférést a privát gépekhez.
- **HTTPS listener** ACM tanúsítvánnyal, a 80-as port átirányításával.
- **NAT Gateway AZ-nként**, a single point of failure megszüntetésére.
- **NACL-ok** a subnetek szintjén (a VPC modulba, a route táblák mellé).
- **Az SSH összekötő szabály a rootba:** a bastion → EC2 szabály jelenleg az EC2 modulban van. Az ALB-hez hasonlóan a rootba téve az EC2 modulnak nem kellene tudnia a bastionról, és a két modul teljesen független lenne egymástól.
- **Verziózott state bucket**, a state véletlen törlése vagy felülírása elleni védelemként (a teardownnak ekkor a régi verziókat is törölnie kell).
