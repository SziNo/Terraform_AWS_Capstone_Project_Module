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

Egy VPC-n belül minden subnet eléri a többit: minden route táblában van egy automatikus `local` route a VPC teljes CIDR-jére. Ezért az ALB és a gépek között nem kell route-ot írni; hogy ki kihez beszélhet, azt a security groupok döntik el.

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

A root modul a közös dolgokat birtokolja (provider, backend, key pair, AMI data source), és a modulok közötti kapcsolatokat (modulhívások, összekötő SG szabály, outputok). A modulok csak azt látják, amit bemenetként kapnak, és csak azt adják ki, amit outputként exportálnak.

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

## Security groupok

Minden szerepnek (bastion, EC2, ALB) saját SG-je van a saját moduljában. Egy SG azt írja le, mi juthat be az adott szerepű gépekre. Az SG valójában a gépek hálózati interfészéhez (ENI) tartozik: az EC2 és a bastion instance-ok primary ENI-jén, illetve az ALB node-jainak ENI-jein.

Egy szabálynak két fontos mezője van:

- `security_group_id` = **hova**: melyik SG szabálylistájába kerül a szabály, vagyis kiknek a gépeit védi
- `referenced_security_group_id` = **honnan**: azok a gépek jöhetnek, amelyek ezt az SG-t viselik (mint egy belépőkártya). A forrás lehet IP-tartomány is (`cidr_ipv4`), pl. a saját IP-d vagy `0.0.0.0/0`.

Apply után a három SG szabályai:

| SG             | Irány | Szabály                      | Ki hozta létre                |
| -------------- | ----- | ---------------------------- | ----------------------------- |
| **ALB SG**     | be    | 80 bárhonnan                 | ALB modul                     |
|                | ki    | 80 a VPC-be                  | ALB modul                     |
| **EC2 SG**     | be    | 22 a bastion SG-ből          | EC2 modul                     |
|                | be    | 80 az ALB SG-ből             | root (`http_from_alb_to_ec2`) |
|                | ki    | minden                       | EC2 modul                     |
| **bastion SG** | be    | 22 az `allowed_ssh_cidr`-ről | bastion modul                 |
|                | ki    | 22 a VPC-be                  | bastion modul                 |

A `from_port` és `to_port` egy porttartományt jelöl (egyetlen porthoz mindkettő ugyanaz), az irányt a resource típusa adja (`ingress_rule` / `egress_rule`). A security groupok állapottartók (stateful): egy beengedett kapcsolat válaszforgalma szabály nélkül is visszajut.

## Skálázhatóság

A bemenetek listák vagy mapek, amiket a modulok név szerint kulcsolt mapekké alakítanak (list-to-map minta), és ezeken megy a `for_each`. A resource címek így nevet viselnek index helyett, pl. `module.vpc.aws_subnet.private["private-a"]`, `module.ec2.aws_instance.this["private-a-2"]`.

Az EC2 modul a `main.tf` elején, a `locals` blokkban a subnetenkénti darabszámból gépenkénti mapet készít. A belső `for` subnetenként egy kis mapet csinál, a külső listába gyűjti ezeket, a `merge(...)` pedig egy mappé fésüli őket (a `...` a lista elemeit külön argumentumként adja át, mint a JavaScript spread operátora):

```hcl
instances = merge([
  for subnet, n in var.ec2_config : {
    for i in range(1, n + 1) : "${subnet}-${i}" => subnet
  }
]...)
```

```
{ "private-a" = 2, "private-b" = 1 }
  => { "private-a-1" = "private-a", "private-a-2" = "private-a", "private-b-1" = "private-b" }
```

Példák, amikhez csak a `terraform.tfvars`-t kell módosítani:

- **Új subnet:** egy új sor a `subnets` listában → a plan csak a subnetet és az associationjét hozza létre.
- **Több gép egy subnetben:** `"private-a" = 3` → létrejön a `private-a-3` gép, és automatikusan bekerül az ALB target groupjába. A lánc: az EC2 modul `instance_ids` outputjában megjelenik az új kulcs → a root ezt adja át az ALB modulnak (`target_instance_ids`) → az attachment `for_each`-e ugyanezen a mapen megy, így új kulcs = új attachment.
- **Gép elvétele:** a kulcsokat a `range(1, n + 1)` generálja, így a darabszám csökkentésekor mindig a legnagyobb sorszámú kulcs tűnik el, és csak az a gép törlődik. Egy középső gépet így nem lehet célzottan kivenni.
- **Új bastion:** egy új elem a `bastion_config` listában.

Hibás bemenetet a változók validációi már a plan elején jeleznek: ismeretlen subnet típus, nem létező vagy nem public NAT subnet, ismeretlen subnet az `ec2_config`-ban vagy a `bastion_config`-ban, duplikált bastion név, negatív vagy tört gépszám, egynél kevesebb ALB subnet, nem engedélyezett instance típus.

## Tervezési döntések

- **A key pair a rootban van**, a feladat leírásával ellentétben (az EC2 modul helyett). Az EC2 gépek és a bastionok is használják, ezért a legközelebbi közös szülőbe került. Így mindkét modul egyenrangúan kapja a kulcs nevét, és a két modul nem függ kölcsönösen egymástól. A root ugyanígy birtokolja a közös AMI data source-t is.
- **A security group szabályok külön resource-ok** (`aws_vpc_security_group_ingress_rule` / `egress_rule`), nem inline `ingress {}` / `egress {}` blokkok. Egy inline szabálylista azt jelenti, hogy „ennek az SG-nek pontosan ezek a szabályai”, és a Terraform minden futásnál törölné, amit valaki más (pl. a root) adott hozzá, majd az visszarakná, oda-vissza. Külön resource-oknál mindenki csak a saját szabályát kezeli, így több helyről is lehet szabályt adni ugyanahhoz az SG-hez.
- **Az ALB → EC2 összekötő szabály a rootban van** (`http_from_alb_to_ec2`, a `main.tf` végén). Egyetlen szabályt ír az EC2 SG-be: a 80-as porton jöhet forgalom az ALB SG-t viselő gépekről. Azért a rootban, mert két modul SG-jét köti össze, így egyik modulnak sem kell tudnia a másikról. SG-hivatkozás (és nem IP) azért, mert az ALB node-jainak IP-címei változhatnak.
- **Legkisebb jogosultság (least privilege):** a bastion kifelé csak SSH-t indíthat a VPC-n belülre, internet-hozzáférése nincs (routing szempontból lenne, az IGW-n át, a security group tiltja). Az ALB kifelé csak HTTP-t a VPC-be. A bastiont nem frissítjük helyben; ha új csomag vagy javítás kell, friss AMI-ból újraépül (immutable infrastructure).
- **A NAT Gateway helye explicit** (`nat_subnet = "public-a"`), validációval. Pozíció alapú választásnál (pl. „az ábécérendben első public subnet”) egy új, előrébb soroló subnet (pl. `public-0`) felvétele megváltoztatná a NAT subnetjét, ami a NAT cseréjével (és kiesésével) járna.
- **A `private_subnet_ids` output a route table associationöktől függ** (`depends_on`), így a privát gépek csak akkor indulnak, amikor a NAT route már él, és a user data `dnf install` parancsa nem hasal el boot közben.
- **IMDSv2 kötelező** minden gépen (`metadata_options { http_tokens = "required" }`). Minden EC2-n fut egy metadata szolgáltatás (`169.254.169.254`), amiből a gép lekérdezheti a saját adatait, és ha van IAM role-ja, annak ideiglenes kulcsait is. Az IMDSv1 sima GET kéréssel működik, amit egy SSRF-típusú támadás kihasználhat; az IMDSv2 előbb tokent kér. A beállítás a gép tulajdonsága, ezért minden gépen ott van; a user data script emiatt kér tokent az instance ID lekérdezéséhez.
- **`default_tags` a providerben:** az `Environment`, `Project` és `ManagedBy` tag minden erőforrásra automatikusan rákerül, a modulokban csak a `Name` tag szerepel.
- **Csak `t2.micro`** engedélyezett (root szintű validáció), a free tier miatt. A validáció a rootban van, nem a modulban, mert ez a fiók korlátja, nem a modulé.
- **Remote state S3-ban, `use_lockfile`-lal.** A feladat S3 + DynamoDB-t említ; a `use_lockfile` az újabb, S3-natív locking, ami a DynamoDB-s megoldást váltja. A bucket tudatosan **verziózás nélküli**: egyszerűbb a takarítás, cserébe egy véletlenül törölt vagy felülírt state nem állítható vissza.
- **Egyetlen NAT Gateway** költségkímélésből. Ha annak az AZ-ja kiesik, egyik privát subnet sem éri el az internetet (single point of failure).
- **Az AMI `most_recent = true`**: ha az Amazon új AMI-t ad ki, a következő plan a gépek cseréjét mutatja. Mivel a környezet minden alkalommal felépül és lebomlik, ez itt nem okoz gondot. A név filter (`al2023-ami-2023.*`) kizárja a minimal image-eket.

## Előfeltételek

- Terraform >= 1.16, AWS CLI beállított hitelesítéssel, régió: `eu-west-1`
- `ssh-agent` (az SSH ugráshoz), `jq` (opcionális, a JSON outputokhoz)

## Telepítés lépésről lépésre

1. **SSH kulcspár generálása** (egyszer; a privát kulcs a gépeden marad, csak a publikus kerül az AWS-be):

   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/capstone-module-key -C "capstone-module"
   cat ~/.ssh/capstone-module-key.pub
   ```

2. **A `terraform.tfvars` elkészítése** a minta alapján. A `key_pair.public_key` a `.pub` fájl tartalma.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

3. **A saját publikus IP ellenőrzése** minden apply előtt (otthoni internetnél változhat). Ha eltér, írd át az `allowed_ssh_cidr`-t (`<ip>/32`), különben nem tudsz SSH-zni a bastionokra.

   ```bash
   curl -s https://checkip.amazonaws.com
   ```

4. **A state bucket létrehozása** (egyszer, verziózás nélkül):

   ```bash
   aws s3 mb s3://szino-terraform-state --region eu-west-1
   ```

5. **A backend bekapcsolása:** a `versions.tf`-ben vedd le a kommentet a `backend "s3"` blokkról, majd:

   ```bash
   terraform init
   ```

   Mivel még nincs lokális state, nincs mit migrálni, a sima `init` elég.

6. **Ellenőrzés:**

   ```bash
   terraform fmt -recursive
   terraform validate
   terraform plan
   ```

   A plan az alapértékekkel: `Plan: 43 to add, 0 to change, 0 to destroy.` Ha a szám nem egyezik, modulonkénti bontás:

   ```bash
   terraform plan -no-color | grep "will be created" | grep -oE "module\.[a-z0-9_-]+" | sort | uniq -c
   ```

7. **Apply** (kb. 5 perc; a NAT Gateway és az ALB a leglassabb):

   ```bash
   terraform apply
   ```

## Tesztelés

### 0. Előkészítés (a saját gépeden, a projekt gyökeréből)

```bash
terraform output                          # címek, ID-k, kész SSH parancsok – innen másolsz
eval "$(ssh-agent -s)"                    # elindítja az agentet ebben a terminálban
ssh-add ~/.ssh/capstone-module-key        # betölti a kulcsot
ssh-add -l                                # ellenőrzés: kiírja a betöltött kulcsot
```

Az outputok kényelmi célt szolgálnak: a Terraform nem futtat semmit, csak összerakja a kész parancsokat, így semmit nem kell kikeresni a konzolban. Az agent a `ssh -J` ugráshoz kell, mert a `-i` kapcsoló csak az utolsó kapcsolatra vonatkozik, a jump hostra (bastion) nem. Az agent terminálonként él, új terminálban újra kell futtatni.

### 1. Outputok

```bash
terraform output
```

**Várt eredmény:** a `bastions` és `ec2_instances` táblázatosan igazítva, minden gép a saját subnetjének tartományában (`10.0.1–3.x` public, `10.0.4–6.x` private), kész SSH parancsok a `ssh_bastions` és `ssh_ec2_instances` alatt.

### 2. SSH a privát gépre a bastionon keresztül

```bash
ssh -J ec2-user@<bastion-1 IP> ec2-user@<private-a-1 IP>    # a ssh_ec2_instances outputból
```

**Várt eredmény:** az első alkalommal két host kulcs kérdés jön (a bastioné és a privát gépé, két külön kapcsolat), mindkettőre `yes`, utána bejutás a privát gépre.

A `-J` (ProxyJump) két kapcsolatot épít: a gépedről a bastionra, és azon alagútként át a privát gépre. A hitelesítés mindkét kapcsolatnál a te gépedről történik, a privát kulcs nem kerül a bastionra. Ezért biztonságosabb, mint a kulcs átmásolása vagy az agent forwarding (`ssh -A`).

### 3. A privát gépen: user data, IMDSv2, NAT

```bash
systemctl status nginx                    # active (running), enabled  (kilépés: q)
curl -s localhost                         # Hello from i-...  (a gép saját instance ID-ja)
curl -s https://checkip.amazonaws.com     # meg kell egyeznie a nat_public_ip outputtal
```

**Mit bizonyít:**

- az nginx fut, tehát a `dnf install` boot közben sikeres volt, vagyis a NAT route már élt (a `depends_on` működik)
- az instance ID megegyezik az outputtal, tehát a script az IMDSv2 tokennel működik
- a kimenő IP megegyezik a `nat_public_ip`-vel, tehát a privát gép a NAT-on megy ki

### 4. A bastionon: negatív teszt (új terminálban is lehet)

```bash
ssh -i ~/.ssh/capstone-module-key ec2-user@<bastion-1 IP>   # itt nem kell az agent
curl -m 5 https://checkip.amazonaws.com                     # Connection timed out
```

**Várt eredmény:** időtúllépés. A bastion egyetlen egress szabálya SSH a VPC-n belülre, a `curl` viszont a bastion által kifelé indított új kapcsolat lenne. Az SSH befelé mégis működik, mert azt az ingress szabály engedi, és a válaszforgalom stateful módon kimehet. A `timed out` (és nem `refused`) azért jön, mert az SG csendben eldobja a nem engedélyezett csomagokat.

### 5. ALB (a saját gépeden, a projekt gyökeréből)

A target group health checkje kb. egy perc után jelöli healthy-nek a gépeket. Az URL böngészőben is megnyitható.

```bash
ALB_URL=$(terraform output -raw alb_url)
for i in $(seq 1 30); do curl -s "$ALB_URL"; done | sort | uniq -c
curl -s "$ALB_URL/health"                 # OK
```

**Várt eredmény:** mind a négy instance ID megjelenik, mindegyik mellett azzal, hány kérést kapott a 30-ból (nagyjából egyenletesen). Ha valamelyik hiányzik, az a gép `unhealthy` a target groupban. A teszt egyben a root összekötő szabályát is igazolja: enélkül az ALB nem érné el a gépeket.

Ha a gépek `unhealthy`-k maradnak, két független dolgot érdemes ellenőrizni:

|             | Target group regisztráció      | Összekötő SG szabály                                |
| ----------- | ------------------------------ | --------------------------------------------------- |
| Mit mond    | „ide küldd a forgalmat”        | „engedd be, ha az ALB küldi”                        |
| Ha hiányzik | az ALB nem tudja, hova küldjön | az EC2 ajtaja nem engedi be, a health check elhasal |

### 6. Skálázhatóság (csak plan, a lebontás előtt)

A `terraform.tfvars`-ban: `"private-a" = 3`, majd:

```bash
terraform plan
```

**Várt eredmény:** `Plan: 2 to add, 0 to change, 0 to destroy`:

- `module.ec2.aws_instance.this["private-a-3"]`
- `module.alb.aws_lb_target_group_attachment.this["private-a-3"]`

Egyik meglévő erőforráshoz sem nyúl. Utána állítsd vissza 2-re, apply nélkül.

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

Az AWS-ben lévő key pairt a `destroy` törli, mert a Terraform hozta létre és benne van a state-ben. A lokális kulcsokhoz (`~/.ssh/capstone-module-key` és `.pub`) a Terraform nem nyúl; ezek maradjanak meg, a következő apply ugyanabból a publikus kulcsból hozza létre újra az AWS key pairt.

## Költségek

A NAT Gateway és az ALB óradíjas, és minden publikus IPv4 cím is (a bastionoké és a NAT Elastic IP-je is), akkor is, ha használatban van. A tesztek után érdemes azonnal lebontani a környezetet.

## Továbbfejlesztési lehetőségek

- **Bastion helyett SSM Session Manager vagy EC2 Instance Connect Endpoint:** publikus IP és nyitott 22-es port nélkül ad hozzáférést a privát gépekhez.
- **HTTPS listener** ACM tanúsítvánnyal, a 80-as port átirányításával.
- **NAT Gateway AZ-nként**, a single point of failure megszüntetésére.
- **NACL-ok** a subnetek szintjén (a VPC modulba, a route táblák mellé, mert a subnethez kötődnek, nem a gépekhez).
- **Az SSH összekötő szabály a rootba:** a bastion → EC2 szabály jelenleg az EC2 modulban van. Az ALB-hez hasonlóan a rootba téve az EC2 modulnak nem kellene tudnia a bastionról, és a két modul teljesen független lenne egymástól.
- **Verziózott state bucket**, a state véletlen törlése vagy felülírása elleni védelemként (a teardownnak ekkor a régi verziókat is törölnie kell).
