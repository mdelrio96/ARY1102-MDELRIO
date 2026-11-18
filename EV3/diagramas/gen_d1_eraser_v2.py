#!/usr/bin/env python3
"""
D1 v2 TO-BE híbrido de FreshBox (EP3) en formato FREEFORM de Eraser.io.

Parte de gen_d1_eraser.py (v1). A diferencia de la v1, reproduce la misma composición y las
mismas coordenadas que gen_d1_hibrido_tobe_v2.py (.drawio v2): arquitectura lógica arriba,
franja VPC con 2 AZ x 3 capas (6 subredes), Security Groups y notas abajo, y paneles a la
derecha (componentes, IAM, leyenda de flechas y flujos).

Cada componente es una tarjeta: Shape (marco) + Icon + Shape de título + Shape de detalle.
Los números 1-14 van en círculos azules, como en el diagrama de referencia del docente.

Uso:
    python gen_d1_eraser_v2.py D1_FreshBox_Hibrido_TOBE_eraser_v2.json
Luego, con el MCP de Eraser:
    manually_create_diagram(fileId, diagramType="freeform-diagram", code=<JSON compacto>)
    export_diagram(fileId, diagramId, format="png", background=true, theme="light")

Esquema freeform verificado (15-nov-2026): Relationship.points debe empezar en [0, 0] y es
relativo a (x, y); las flechas pueden unir Shapes, Icons y Groups. Íconos usados y probados:
users, shield, lock, aws-vpc, aws-s3, aws-api-gateway, aws-lambda, aws-dynamodb, aws-sqs,
aws-eks, aws-rds, aws-ec2, aws-elb-application-load-balancer, aws-nat-gateway,
aws-internet-gateway, aws-vpc-endpoints, aws-elastic-container-registry, aws-cloudwatch,
aws-key-management-service, aws-route-table.
"""
import json
import sys

VERDE = {"fill": "#E9F3DF", "stroke": "#3F8F29", "text": "#2E6B1E"}
AZUL = {"fill": "#E6F0FA", "stroke": "#1F6FB2", "text": "#0B4F79"}
MORADO = {"fill": "#EFE6F7", "stroke": "#7D3C98", "text": "#5A2D82"}
NARANJA = {"fill": "#FFF3E0", "stroke": "#D86613", "text": "#7A3A00"}
ROJO = {"fill": "#FDECEE", "stroke": "#DD344C", "text": "#7D0000"}
DARK, GRIS_TXT = "#16324F", "#5A6B7B"
NET, COMP, DB, INTEG, STOR, MGMT, SEC = "#8C4FFF", "#ED7100", "#C925D1", "#E7157B", "#7AA116", "#E7157B", "#DD344C"
C_PUB, C_APP, C_DAT = "#3F8F29", "#1F6FB2", "#7D3C98"
COLOR = {"sync": "#1F4E9E", "async": "#7D3C98", "sup": "#7F8C8D", "dat": "#7D3C98"}

els = []
_n = [0]


def nid(p):
    _n[0] += 1
    return f"{p}{_n[0]}"


def n(v):
    """Coordenada sin decimales cuando es entera (JSON más corto)."""
    return int(v) if float(v).is_integer() else round(v, 1)


def icon(name, x, y, w=48, h=48, label=None, fs=12, container=None, color=None, size="md"):
    e = {"tag": "Icon", "id": nid("i"), "icon": name, "x": n(x), "y": n(y), "width": n(w), "height": n(h)}
    if size != "md":
        e["size"] = size
    if label:
        e["texts"] = [{"text": label, "fontSize": fs}]
    if container:
        e["containerId"] = container
    if color:
        e["color"] = color
    els.append(e)
    return e["id"]


def group(title, x, y, w, h, fill, stroke, font, fs=13, dashed=False, gicon=None, container=None):
    t = {"text": title, "color": font, "fontSize": fs}
    if gicon:
        t["icon"] = gicon
    e = {"tag": "Group", "id": nid("g"), "x": x, "y": y, "width": w, "height": h,
         "bgColor": fill, "borderColor": stroke, "title": t}
    if dashed:
        e["borderStyle"] = "dashed"
    if container:
        e["containerId"] = container
    els.append(e)
    return e["id"]


def shape(text, x, y, w, h, fill="transparent", stroke="transparent", color=DARK, fs=11, bold=False,
          dashed=False, kind="rectangle", container=None):
    e = {"tag": "Shape", "id": nid("s"), "shape": kind, "x": n(x), "y": n(y), "width": n(w), "height": n(h),
         "bgColor": fill, "borderColor": stroke, "styleMode": "plain"}  # sin styleMode Eraser dibuja sombra
    if text:
        partes = text if isinstance(text, list) else [(text, fs, bold)]
        e["texts"] = []
        for txt, f, b in partes:
            t = {"text": txt, "fontSize": f}
            if color != DARK:          # el color por defecto de Eraser ya es oscuro
                t["color"] = color
            if b:
                t["bold"] = True
            e["texts"].append(t)
    if dashed:
        e["borderStyle"] = "dashed"
    if container:
        e["containerId"] = container
    els.append(e)
    return e["id"]


def rel(src, dst, path, label="", fp="bottom", tp="top", kind="sync"):
    x, y = path[0]
    e = {"tag": "Relationship", "id": nid("r"), "from": src, "to": dst, "fromPort": fp, "toPort": tp,
         "x": n(x), "y": n(y), "width": 0, "height": 0,
         "points": [[0, 0]] + [[n(px - x), n(py - y)] for px, py in path[1:]],
         "endArrowhead": "triangle", "lineStyle": "dashed" if kind in ("async", "sup") else "solid",
         "color": COLOR[kind], "lineWidth": 2}
    if label:
        e["label"] = label
        e["textSize"] = "small"
    els.append(e)
    return e["id"]


def badge(n, x, y):
    return shape(str(n), x, y, 26, 26, fill="#1F4E9E", stroke="#FFFFFF", color="#FFFFFF", fs=12, bold=True, kind="ellipse")


def chip(txt, color, x, y, w=104):
    return shape(txt, x, y, w, 18, fill=color, color="#FFFFFF", fs=10, bold=True)


def card(x, y, w, h, ic, title, detail, stroke, num=None, subnet=None, isz=48):
    c = shape("", x, y, w, h, fill="#FFFFFF", stroke=stroke)
    icon(ic, x + 12, y + (h - isz) / 2, isz, isz)
    tx = x + 24 + isz
    shape([(title, 13, True), (detail, 11, False)], tx, y + 4, x + w - tx - 6, h - 8)
    if num is not None:
        badge(num, x - 12, y - 12)
    if subnet:
        chip(subnet[0], subnet[1], x + w - 112, y - 9)
    return c


def panel(x, y, w, h, titulo):
    shape("", x, y, w, h, fill="#FFFFFF", stroke="#9AA5B1")
    shape(titulo, x, y, w, 32, fill=DARK, stroke=DARK, color="#FFFFFF", fs=13, bold=True)


def build():
    # título
    shape("ARQUITECTURA TO-BE HÍBRIDA · FRESHBOX SPA", 20, 8, 1450, 36, fs=24, bold=True)
    shape("Amazon EKS para el CRUD de productos · Lambda, DynamoDB y SQS para carrito y órdenes · frontend en S3 · us-east-1",
          20, 46, 1450, 22, fs=13, color="#1F3A5F")

    # fila A: entrada
    users = icon("users", 40, 116, 58, 58, label="Usuarios\n(navegador)")
    s3 = card(170, 95, 250, 100, "aws-s3", "Amazon S3", "Static Website Hosting\nfreshbox-frontend-<cuenta>", STOR, num=1)
    api = card(520, 95, 270, 100, "aws-api-gateway", "Amazon API Gateway",
               "freshbox-api · REST · stage prod\nentrada única · CORS", INTEG, num=2)
    alb = card(1180, 95, 290, 100, "aws-elb-application-load-balancer", "ALB Ingress (EKS)",
               "HTTP Integration · internet-facing\nuna regla por método · SG-ALB", NET, num=8, subnet=("PÚBLICA", C_PUB))
    rel(users, s3, [(98, 145), (170, 145)], "HTTP 80", fp="right", tp="left")
    rel(s3, api, [(420, 145), (520, 145)], "fetch · HTTPS 443", fp="right", tp="left")
    rel(api, alb, [(790, 145), (1180, 145)], "/api/products · GET · POST · PUT · DELETE", fp="right", tp="left")
    shape("HTTP 80 · vía IGW", 880, 150, 210, 18, fs=10, color=COLOR["sync"])

    # fila B: Lambdas de entrada y ECR
    cart = card(40, 290, 260, 100, "aws-lambda", "Lambda Cart", "freshbox-procesar-carrito\nPOST · GET · DELETE del carrito",
                COMP, num=3)
    corder = card(360, 290, 290, 100, "aws-lambda", "Lambda Create-Order",
                  "freshbox-crear-orden\nlee el carrito, calcula el total\ny publica la orden en SQS", COMP, num=4)
    rel(api, cart, [(600, 195), (600, 250), (170, 250), (170, 290)], "/api/cart · GET · POST · DELETE")
    rel(api, corder, [(600, 195), (600, 250), (505, 250), (505, 290)], "/api/orders · POST")
    ecr = card(860, 300, 250, 80, "aws-elastic-container-registry", "Amazon ECR",
               "4 repositorios freshbox-*\nimágenes linux/arm64", COMP, isz=40)

    # fila C: DynamoDB, SQS (+DLQ), Process-Order
    ddb = card(40, 460, 260, 100, "aws-dynamodb", "Amazon DynamoDB",
               "carrito-freshbox · on-demand\nPK userId · SK productId\nTTL expiresAt = 24 h", DB, num=6)
    sqs = card(500, 460, 280, 100, "aws-sqs", "Amazon SQS",
               "ordenes-freshbox · cifrada (SSE)\nentrega por lotes a Process-Order", INTEG, num=7)
    po = card(850, 460, 280, 100, "aws-lambda", "Lambda Process-Order",
              "freshbox-procesar-orden\ntrigger SQS · INSERT en RDS\nENI en APP 1a y 1b (SG-LAMBDA)", COMP, num=5,
              subnet=("PRIVADA APP", C_APP))
    dlq = card(575, 584, 210, 52, "aws-sqs", "DLQ", "ordenes-freshbox-dlq", INTEG, isz=32)
    rel(cart, ddb, [(170, 390), (170, 460)], "Put · Query · Delete")
    rel(corder, ddb, [(418, 390), (418, 510), (300, 510)], "Query carrito", tp="right")
    rel(corder, sqs, [(592, 390), (592, 460)], "SendMessage", kind="async")
    rel(sqs, po, [(780, 510), (850, 510)], "trigger (lotes)", fp="right", tp="left", kind="async")
    rel(sqs, dlq, [(680, 560), (680, 584)], kind="async")
    shape("tras 3 intentos fallidos", 690, 563, 150, 16, color=COLOR["async"], fs=10, bold=True)

    # VPC Endpoint Gateway
    vpce = card(400, 660, 260, 80, "aws-vpc-endpoints", "VPC Endpoint Gateway",
                "DynamoDB · asociado a la RT APP\nsin salir a Internet · sin costo", NET, num=11, isz=44)
    rel(po, vpce, [(900, 560), (900, 700), (660, 700)], "borra el carrito · HTTPS 443", tp="right")
    rel(vpce, ddb, [(400, 700), (170, 700), (170, 560)], "acceso privado", fp="left", tp="bottom")

    # columna derecha: EKS, RDS, CloudWatch, KMS
    eks = shape("", 1180, 285, 290, 300, fill="#FFFFFF", stroke=COMP)
    icon("aws-eks", 1192, 293, 36, 36)
    shape("Amazon EKS · freshbox-cluster", 1236, 291, 228, 20, fs=12, bold=True)
    shape("CRUD de productos (4 Deployments)", 1236, 311, 228, 18, fs=11)
    badge(9, 1168, 273)
    chip("PRIVADA APP", C_APP, 1358, 276)
    shape("", 1192, 341, 266, 196, fill="#FFF8F0", stroke=COMP, dashed=True)
    pods = [("get-products", "GET · :3001"), ("create-product", "POST · :3002"),
            ("update-product", "PUT · :3003"), ("delete-product", "DELETE · :3004")]
    for k, (nombre, metodo) in enumerate(pods):
        shape(f"{nombre}\n{metodo}", 1200 + (k % 2) * 130, 352 + (k // 2) * 92, 120, 82,
              fill="#EAF1FF", stroke="#326CE5", fs=11, bold=True)
    shape("2 réplicas por Deployment (1 por AZ) · HPA 2–5\nNode Group 2–4 × t4g.small · EBS cifrado",
          1185, 541, 280, 32, color=GRIS_TXT, fs=10)
    rel(alb, eks, [(1325, 195), (1325, 285)], "HTTP :3001–3004")
    rel(ecr, eks, [(1110, 340), (1180, 340)], "pull de imágenes", fp="right", tp="left", kind="sup")

    rds = card(1180, 640, 290, 100, "aws-rds", "Amazon RDS MySQL 8.0",
               "Multi-AZ · db.t4g.small · cifrada\nprimaria 1a · standby 1b\nproductos y órdenes", DB, num=10,
               subnet=("PRIVADA DATA", C_DAT))
    rel(eks, rds, [(1325, 585), (1325, 640)], "MySQL 3306")
    rel(po, rds, [(1070, 560), (1070, 690), (1180, 690)], "INSERT orden · MySQL 3306", tp="left")
    card(1180, 756, 290, 58, "aws-cloudwatch", "Amazon CloudWatch",
         "logs de Lambda, API Gateway y EKS\nmétricas de RDS y SQS", MGMT, isz=36)
    card(1180, 824, 290, 58, "aws-key-management-service", "AWS KMS",
         "cifrado en reposo de EBS, RDS,\nSQS y DynamoDB", SEC, isz=36)

    # franja VPC (13): 2 AZ x 3 capas
    vpc = group("VPC freshbox-vpc · 10.0.0.0/22", 20, 910, 1450, 290, "#FFFFFF", "#3F8F29", "#2E6B1E", fs=14,
                gicon="aws-vpc")
    badge(13, 8, 898)
    igw = icon("aws-internet-gateway", 488, 888, 40, 40)
    shape("Internet Gateway", 534, 888, 150, 18, fs=11, bold=True)
    capas = [(120, 380, VERDE, C_PUB, "Capa 1 · PÚBLICA — RT: 0.0.0.0/0 → Internet Gateway"),
             (515, 525, AZUL, C_APP, "Capa 2 · PRIVADA APP — RT: 0.0.0.0/0 → NAT · DynamoDB → VPC Endpoint (11)"),
             (1055, 395, MORADO, C_DAT, "Capa 3 · PRIVADA DATA — RT: solo ruta local")]
    for x, w, p, c, t in capas:
        shape("", x, 940, w, 28, fill=p["fill"], stroke=c, container=vpc)
        icon("aws-route-table", x + 6, 943, 22, 22, container=vpc)
        shape(t, x + 32, 940, w - 36, 28, color=p["text"], fs=11, bold=True, container=vpc)
    for ay, lab in ((975, "AZ1a\nus-east-1a"), (1085, "AZ1b\nus-east-1b")):
        shape("", 30, ay, 1430, 100, stroke="#1F6FB2", dashed=True, container=vpc)
        shape(lab, 34, ay, 82, 100, color="#1F6FB2", fs=12, bold=True, container=vpc)

    cidr = {"pub": ["10.0.0.0/25", "10.0.0.128/25"], "app": ["10.0.1.0/25", "10.0.1.128/25"],
            "dat": ["10.0.2.0/25", "10.0.2.128/25"]}

    def sitem(ic, x, y, label, lw, container, lx=None):
        i = icon(ic, x, y, 36, 36, container=container)
        shape(label, x + 42 if lx is None else lx, y - 4, lw, 44, fs=10, bold=True, container=container)
        return i

    pubs, nodes, rdss = [], [], []
    for k, sy in enumerate((982, 1092)):
        az = "1a" if k == 0 else "1b"
        iy = sy + 36
        gp = group(f"Pública {az} · {cidr['pub'][k]}", 120, sy, 380, 86, VERDE["fill"], VERDE["stroke"], VERDE["text"],
                   fs=12, gicon="lock", container=vpc)
        ga = group(f"Privada APP {az} · {cidr['app'][k]}", 515, sy, 525, 86, AZUL["fill"], AZUL["stroke"], AZUL["text"],
                   fs=12, gicon="lock", container=vpc)
        gd = group(f"Privada DATA {az} · {cidr['dat'][k]}", 1055, sy, 395, 86, MORADO["fill"], MORADO["stroke"],
                   MORADO["text"], fs=12, gicon="lock", container=vpc)
        pubs.append(gp)
        sitem("aws-elb-application-load-balancer", 140, iy, f"(8) ALB · nodo {az}", 150, gp)
        nodes.append(sitem("aws-ec2", 535, iy, "(9) Nodo EKS t4g.small\n4 pods CRUD", 200, ga))
        sitem("aws-lambda", 800, iy, "(5) ENI de Process-Order\n(SG-LAMBDA)", 196, ga)
        if k == 0:
            nat = sitem("aws-nat-gateway", 450, iy, "NAT Gateway\n(único, en 1a)", 106, gp, lx=338)
            rdss.append(sitem("aws-rds", 1075, iy, "(10) RDS primaria\nlectura y escritura", 220, gd))
        else:
            rdss.append(sitem("aws-rds", 1075, iy, "(10) RDS standby\nsincrónica, sin tráfico", 220, gd))

    rel(igw, pubs[0], [(508, 928), (508, 1000), (500, 1000)], tp="right")
    rel(nodes[0], nat, [(535, 1036), (486, 1036)], fp="left", tp="right", kind="sup")
    rel(nodes[1], nat, [(535, 1146), (508, 1146), (508, 1036), (486, 1036)], fp="left", tp="right", kind="sup")
    rel(rdss[0], rdss[1], [(1093, 1054), (1093, 1128)], kind="dat")
    shape("replicación sincrónica (Multi-AZ)", 1102, 1072, 200, 16, color=C_DAT, fs=10, bold=True)

    # Security Groups (12)
    shape("", 20, 1220, 1450, 130, fill="#FFFFFF", stroke="#9AA5B1")
    badge(12, 8, 1208)
    shape("Security Groups (encadenados)", 40, 1226, 260, 22, fs=13, bold=True)
    sgs = [("SG-ALB", "Entrada: 80/443 desde 0.0.0.0/0\nSalida: 3001–3004 → SG-EKS", ROJO, 40),
           ("SG-EKS", "Entrada: 3001–3004 desde SG-ALB\ny tráfico interno del clúster\nSalida: 3306 → SG-RDS", AZUL, 400),
           ("SG-RDS", "Entrada: 3306 desde SG-EKS\ny SG-LAMBDA\nsin salida a Internet", MORADO, 760),
           ("SG-LAMBDA", "Sin entrada\nSalida: 3306 → SG-RDS\n443 → DynamoDB (prefix list)", NARANJA, 1120)]
    sg_ids = []
    for nombre, regla, p, x in sgs:
        sg_ids.append(shape("", x, 1254, 290, 86, fill=p["fill"], stroke=p["stroke"]))
        icon("shield", x + 10, 1280, 34, 34, color=p["stroke"], size="sm")
        shape([(nombre, 13, True), (regla, 11, False)], x + 52, 1258, 232, 78)
    rel(sg_ids[0], sg_ids[1], [(330, 1297), (400, 1297)], "3001–3004", fp="right", tp="left")
    rel(sg_ids[1], sg_ids[2], [(690, 1297), (760, 1297)], "3306", fp="right", tp="left")
    rel(sg_ids[3], sg_ids[2], [(1120, 1297), (1050, 1297)], "3306", fp="left", tp="right")

    # notas
    shape("", 20, 1370, 1450, 126, fill="#FFFFFF", stroke="#9AA5B1")
    shape("NOTAS IMPORTANTES", 40, 1376, 200, 22, fs=13, bold=True)
    notas = [
        "Escalabilidad: Lambda escala por solicitud; HPA de 2 a 5 réplicas por Deployment; Node Group de 2 a 4 nodos.",
        "Desacoplamiento: SQS separa la respuesta al cliente del registro en RDS; tras 3 intentos el mensaje pasa a la DLQ.",
        "Seguridad: SG encadenados por capa, RDS solo en subredes DATA, DynamoDB por VPC Endpoint, cifrado con KMS.",
        "Alta disponibilidad: ALB, nodos EKS y RDS en 2 AZ. NAT único (1a) por costo: si cae la AZ1a, APP 1b pierde la salida.",
        "Lambda y la VPC: solo Process-Order se conecta a la VPC (necesita RDS); Cart y Create-Order quedan fuera.",
        "API Gateway → ALB: HTTP 80 por Internet (el lab no tiene certificado ACM); mejora propuesta: VPC Link con NLB.",
    ]
    # notas en dos bloques (una forma por columna, para mantener el JSON bajo el límite del MCP)
    shape("\n".join(notas[:3]), 40, 1402, 690, 90, fs=11)
    shape("\n".join(notas[3:]), 760, 1402, 690, 90, fs=11)

    # ---- desde aquí, paneles laterales: van en un segundo diagrama del mismo archivo de Eraser
    corte[0] = len(els)

    # panel 1: componentes (un bloque de texto; los números 1-14 son los de los círculos azules)
    PX, PW = 20, 460
    panel(PX, 20, PW, 330, "COMPONENTES DEL DISEÑO")
    comps = [
        "1 · Amazon S3 · sitio estático (HTML, CSS, JS)", "2 · API Gateway · rutas a Lambda y al ALB",
        "3 · Lambda Cart · CRUD del carrito en DynamoDB", "4 · Lambda Create-Order · total y publicación en SQS",
        "5 · Lambda Process-Order · consume SQS, escribe en RDS", "6 · DynamoDB · tabla carrito con TTL de 24 h",
        "7 · SQS · cola ordenes con DLQ", "8 · ALB Ingress · HTTP Integration, regla por método",
        "9 · EKS · 4 pods (GET, POST, PUT, DELETE)", "10 · RDS MySQL · Multi-AZ (primaria 1a, standby 1b)",
        "11 · VPC Endpoint Gateway · DynamoDB desde la VPC", "12 · Security Groups · SG-ALB, SG-EKS, SG-RDS, SG-LAMBDA",
        "13 · VPC · 6 subredes: pública, APP y DATA en 2 AZ", "14 · Flechas · síncrono, asíncrono y soporte",
        "Soporte · Internet Gateway, NAT Gateway, ECR, CloudWatch y KMS",
    ]
    shape("\n".join(comps), PX + 10, 40, PW - 20, 300, fs=11)

    # panel 2: IAM
    panel(PX, 370, PW, 230, "IAM ROLES POR LAMBDA")
    shape("Lambda Cart: dynamodb:PutItem · Query · DeleteItem\n"
          "Lambda Create-Order: dynamodb:Query · sqs:SendMessage\n"
          "Lambda Process-Order: sqs:ReceiveMessage · DeleteMessage\n· GetQueueAttributes · dynamodb:Query · BatchWriteItem\n"
          "· ec2:Create/Describe/DeleteNetworkInterface\n"
          "Las tres: logs:CreateLogGroup · CreateLogStream · PutLogEvents", PX + 10, 406, PW - 20, 120, fs=10)
    shape("En el Learner Lab las tres funciones asumen LabRole (no se pueden crear roles IAM).\n"
          "Estas son las políticas mínimas del diseño objetivo.", PX + 10, 532, PW - 20, 56, color=GRIS_TXT, fs=10)

    # panel 3: leyenda de flechas (14)
    LY = 620
    panel(PX, LY, PW, 156, "FLECHAS DE FLUJO")
    badge(14, PX - 12, LY - 12)
    muestras = [("sync", "Flujo síncrono (solicitud y respuesta)\nEj: Usuario → API Gateway → Lambda"),
                ("async", "Flujo asíncrono (desacoplado)\nEj: Create-Order → SQS → Process-Order"),
                ("sup", "Soporte (imágenes y salida a Internet)\nEj: ECR → nodos EKS · nodos APP → NAT")]
    for j, (k, desc) in enumerate(muestras):
        yy = LY + 56 + 38 * j
        a = shape("", PX + 14, yy - 2, 4, 4)
        b = shape("", PX + 86, yy - 2, 4, 4)
        rel(a, b, [(PX + 18, yy), (PX + 86, yy)], fp="right", tp="left", kind=k)
        shape(desc, PX + 100, yy - 18, PW - 110, 36, fs=11)

    # panel 4: flujos de la pauta (2.3)
    FY = LY + 176
    panel(PX, FY, PW, 290, "FLUJOS DE LA APLICACIÓN")
    flujos = [
        "Productos (CRUD)\nS3 → API Gateway → ALB → pod del método\n(GET, POST, PUT, DELETE) → RDS MySQL",
        "Carrito\nS3 → API Gateway → Lambda Cart → DynamoDB\n(el ítem expira a las 24 h por TTL)",
        "Órdenes\nS3 → API Gateway → Create-Order → DynamoDB\n→ SQS → Process-Order → RDS MySQL",
        "Confirmación\nCreate-Order responde con orderId y total; el sitio\nmuestra «Su pedido fue procesado» y Process-Order\n"
        "guarda la orden y vacía el carrito",
    ]
    for j, t in enumerate(flujos):
        shape(t, PX + 10, FY + 40 + 60 * j, PW - 20, 58, fs=11)

    return ({"title": "D1 v2 · Arquitectura TO-BE híbrida FreshBox (EP3)", "elements": els[:corte[0]]},
            {"title": "D1 v2 · Componentes, IAM, flechas y flujos", "elements": els[corte[0]:]})


corte = [0]


def main():
    """Escribe dos JSON: <salida>.json (arquitectura) y <salida>_paneles.json (paneles laterales).
    El MCP de Eraser no admite cómodamente un único JSON de ~45 KB, por eso van como dos diagramas."""
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    arq, pan = build()
    salida = sys.argv[1]
    for datos, ruta in ((arq, salida), (pan, salida.replace(".json", "_paneles.json"))):
        with open(ruta, "w", encoding="utf-8") as f:
            json.dump(datos, f, ensure_ascii=False, indent=1)
        print(f"OK {ruta} ({len(datos['elements'])} elementos)")


if __name__ == "__main__":
    main()
