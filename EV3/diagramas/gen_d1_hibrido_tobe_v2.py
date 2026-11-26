#!/usr/bin/env python3
"""
D1 v2 - Arquitectura TO-BE híbrida de FreshBox SpA: Amazon EKS + serverless (EP3).

Parte de gen_d1_hibrido_tobe.py (v1) y mantiene su composición: arquitectura lógica arriba,
red debajo y paneles a la derecha, con la numeración 1-14 del diagrama de referencia.

Cambios respecto de la v1:
  - Franja VPC como cuadrícula: 2 AZ (filas) x 3 capas (columnas) = las 6 subredes /25 con su
    CIDR. Cada componente de red aparece en su subred real: nodos del ALB en 1a y 1b, NAT único
    en pública 1a, nodos EKS y ENI de Process-Order en APP 1a y 1b, RDS primaria en DATA 1a y
    standby en DATA 1b. Se elimina la caja Multi-AZ suelta de la v1.
  - Route table por capa (cabecera de cada columna) y flechas IGW -> subred pública y
    nodos APP -> NAT, que en la v1 no estaban conectados.
  - Se agregan Amazon ECR (pull de imágenes a los nodos), la DLQ de SQS, CloudWatch y KMS.
  - Rutas de API Gateway con sus métodos en las etiquetas de las flechas (según la guía del docente y app.js).
  - IAM corregido contra el código: Process-Order también hace dynamodb:Query; las tres
    funciones escriben logs en CloudWatch.
  - SG-EKS incluye el tráfico interno del clúster (pauta 2.4).
  - Leyenda con tres tipos de flecha: síncrono, asíncrono y soporte.

Uso:  python gen_d1_hibrido_tobe_v2.py D1_FreshBox_Hibrido_TOBE_v2.drawio
"""
import sys
from xml.sax.saxutils import escape

PAL = {
    "verde":   {"fill": "#E9F3DF", "stroke": "#3F8F29", "text": "#2E6B1E"},
    "azul":    {"fill": "#E6F0FA", "stroke": "#1F6FB2", "text": "#0B4F79"},
    "morado":  {"fill": "#EFE6F7", "stroke": "#7D3C98", "text": "#5A2D82"},
    "rojo":    {"fill": "#FDECEE", "stroke": "#DD344C", "text": "#7D0000"},
    "naranja": {"fill": "#FFF3E0", "stroke": "#D86613", "text": "#7A3A00"},
    "rosa":    {"fill": "#FCE8F1", "stroke": "#E7157B", "text": "#8A0D4A"},
    "gris":    {"fill": "#F2F4F7", "stroke": "#5A6B7B", "text": "#232F3E"},
}
DARK, NET, COMP, DB, K8S, MGMT, SEC = "#16324F", "#8C4FFF", "#ED7100", "#C925D1", "#326CE5", "#E7157B", "#DD344C"
STOR, INTEG = "#7AA116", "#E7157B"
BLUE, PURPLE, GREY = "#1F4E9E", "#7D3C98", "#7F8C8D"
C_PUB, C_APP, C_DAT = "#3F8F29", "#1F6FB2", "#7D3C98"

# Tipos de flecha: continua = síncrono, discontinua = asíncrono, punteada gris = soporte
SYNC = f"strokeColor={BLUE};fontColor={BLUE};fontStyle=1;"
ASYNC = f"strokeColor={PURPLE};fontColor={PURPLE};fontStyle=1;dashed=1;dashPattern=8 4;"
SUP = f"strokeColor={GREY};fontColor=#5A6B7B;fontStyle=1;dashed=1;dashPattern=3 3;"

cells = []
_n = [1]


def nid():
    _n[0] += 1
    return f"n{_n[0]}"


def _val(s):
    return escape(str(s).replace("\n", "<br>"), {'"': "&quot;"})


def vertex(value, style, x, y, w, h):
    i = nid()
    cells.append(f'<mxCell id="{i}" value="{_val(value)}" style="{style}" vertex="1" parent="1">'
                 f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')
    return i


def edge(src, dst, label="", style="", points=None):
    i = nid()
    base = ("edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;fontSize=11;fontColor=#232F3E;endArrow=block;"
            "endFill=1;strokeWidth=2;strokeColor=#232F3E;labelBackgroundColor=#FFFFFF;")
    pts = ""
    if points:
        pts = '<Array as="points">' + "".join(f'<mxPoint x="{px}" y="{py}"/>' for px, py in points) + "</Array>"
    cells.append(f'<mxCell id="{i}" value="{_val(label)}" style="{base}{style}" edge="1" parent="1" source="{src}" target="{dst}">'
                 f'<mxGeometry relative="1" as="geometry">{pts}</mxGeometry></mxCell>')
    return i


def line(x1, y1, x2, y2, style=""):
    """Flecha suelta (sin origen ni destino), para las muestras de la leyenda."""
    i = nid()
    cells.append(f'<mxCell id="{i}" value="" style="rounded=0;html=1;endArrow=block;endFill=1;strokeWidth=2;{style}" edge="1" parent="1">'
                 f'<mxGeometry relative="1" as="geometry"><mxPoint x="{x1}" y="{y1}" as="sourcePoint"/>'
                 f'<mxPoint x="{x2}" y="{y2}" as="targetPoint"/></mxGeometry></mxCell>')
    return i


def icon(res, fill, extra=""):
    return ("sketch=0;outlineConnect=0;fontColor=#232F3E;gradientColor=none;"
            f"fillColor={fill};strokeColor=none;dashed=0;verticalLabelPosition=bottom;"
            "verticalAlign=top;align=center;html=1;fontSize=12;fontStyle=1;aspect=fixed;"
            f"shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.{res};{extra}")


def k8s_icon(pr):
    return (f"html=1;dashed=0;whiteSpace=wrap;fillColor={K8S};strokeColor=#ffffff;points=[[0.005,0.63,0],[0.1,0.2,0],"
            "[0.9,0.2,0],[0.5,0,0],[0.995,0.63,0],[0.72,0.99,0],[0.5,1,0],[0.28,0.99,0]];"
            f"shape=mxgraph.kubernetes.icon;prIcon={pr};aspect=fixed;")


GRP_PTS = ("points=[[0,0],[0.25,0],[0.5,0],[0.75,0],[1,0],[1,0.25],[1,0.5],[1,0.75],[1,1],"
           "[0.75,1],[0.5,1],[0.25,1],[0,1],[0,0.75],[0,0.5],[0,0.25]];")


def group(gr_icon, stroke, fill, font, fs=13):
    return (GRP_PTS + "outlineConnect=0;gradientColor=none;html=1;whiteSpace=wrap;"
            f"fontSize={fs};fontStyle=1;container=0;pointerEvents=0;collapsible=0;recursiveResize=0;"
            f"shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.{gr_icon};grStroke=1;strokeColor={stroke};"
            f"fillColor={fill};verticalAlign=top;align=left;spacingLeft=30;fontColor={font};dashed=0;strokeWidth=2;")


def box(fill, stroke, font, fs=12, align="left", valign="top", dashed=0, bold=1, rounded=1, extra=""):
    return (f"rounded={rounded};whiteSpace=wrap;html=1;fillColor={fill};strokeColor={stroke};fontColor={font};"
            f"fontSize={fs};fontStyle={bold};align={align};verticalAlign={valign};spacing=8;dashed={dashed};strokeWidth=1.5;{extra}")


def text(fs=12, color=DARK, align="left", bold=0, valign="top", bg=None):
    lb = f"labelBackgroundColor={bg};" if bg else ""
    return f"text;html=1;whiteSpace=wrap;fontSize={fs};fontColor={color};align={align};verticalAlign={valign};fontStyle={bold};{lb}"


def badge(n, x, y):
    """Número del componente (1 a 14), como en el diagrama de referencia."""
    return vertex(str(n), "ellipse;whiteSpace=wrap;html=1;fillColor=#1F4E9E;strokeColor=#FFFFFF;strokeWidth=2;"
                  "fontColor=#FFFFFF;fontSize=12;fontStyle=1;align=center;verticalAlign=middle;spacing=0;", x, y, 26, 26)


def chip(txt, color, x, y, w=104):
    """Etiqueta de subred: mismo color que la capa de la franja VPC."""
    return vertex(txt, f"rounded=1;arcSize=50;whiteSpace=wrap;html=1;fillColor={color};strokeColor=#FFFFFF;strokeWidth=1.5;"
                  "fontColor=#FFFFFF;fontSize=10;fontStyle=1;align=center;verticalAlign=middle;spacing=0;", x, y, w, 18)


def card(x, y, w, h, res, fill, title, detail, stroke, num=None, subnet=None, isz=48):
    """Tarjeta de un componente: ícono a la izquierda, nombre y detalle a la derecha."""
    c = vertex("", box("#FFFFFF", stroke, DARK, extra="arcSize=8;strokeWidth=2;"), x, y, w, h)
    vertex("", icon(res, fill), x + 12, y + (h - isz) / 2, isz, isz)
    tx = x + 24 + isz
    vertex(f"<b><font style=\"font-size:13px\">{title}</font></b><br>{detail}",
           text(11, DARK, "left", 0, "middle"), tx, y + 4, x + w - tx - 6, h - 8)
    if num is not None:
        badge(num, x - 12, y - 12)
    if subnet:
        nombre, color = subnet
        chip(nombre, color, x + w - 112, y - 9)
    return c


def panel(x, y, w, h, titulo):
    vertex("", box("#FFFFFF", "#9AA5B1", DARK, extra="arcSize=2;"), x, y, w, h)
    vertex(titulo, box(DARK, DARK, "#FFFFFF", fs=13, align="center", valign="middle", rounded=0), x, y, w, 32)


def sep(x, y, w):
    vertex("", "rounded=0;html=1;fillColor=#D0D5DB;strokeColor=none;", x, y, w, 1)


def build(sin_panel=False):
    W, H = (1490, 1510) if sin_panel else (2000, 1510)
    pub, app, dat = PAL["verde"], PAL["azul"], PAL["morado"]

    # ------------------------------------------------------------------ título
    vertex("ARQUITECTURA TO-BE HÍBRIDA · FRESHBOX SPA", text(26, DARK, "left", 1), 20, 8, 1450, 36)
    vertex("Amazon EKS para el CRUD de productos · Lambda, DynamoDB y SQS para carrito y órdenes · frontend en S3 · us-east-1",
           text(13, "#1F3A5F", "left"), 20, 46, 1450, 22)

    # ------------------------------------------------------------------ fila A: entrada
    users = vertex("Usuarios\n(navegador)", icon("users", "#232F3E"), 40, 116, 58, 58)
    s3 = card(170, 95, 250, 100, "s3", STOR, "Amazon S3", "Static Website Hosting\nfreshbox-frontend-&lt;cuenta&gt;\nlectura pública por política",
              STOR, num=1)
    api = card(520, 95, 270, 100, "api_gateway", INTEG, "Amazon API Gateway",
               "freshbox-api · REST regional\nstage prod · entrada única · CORS\nproxy HTTP al ALB y a Lambda", INTEG, num=2)
    alb = card(1180, 95, 290, 100, "application_load_balancer", NET, "ALB Ingress (EKS)",
               "freshbox-eks-alb · HTTP 80\nuna regla por método · SG-ALB\nlo crea EKS Auto Mode", NET, num=8,
               subnet=("PÚBLICA", C_PUB))

    edge(users, s3, "HTTP 80", SYNC + "exitX=1;exitY=0.5;entryX=0;entryY=0.5;")
    edge(s3, api, "fetch\nHTTPS 443", SYNC + "exitX=1;exitY=0.5;entryX=0;entryY=0.5;")
    edge(api, alb, "/api/products · GET · POST · PUT · DELETE\nHTTP 80 · vía IGW", SYNC + "exitX=1;exitY=0.5;entryX=0;entryY=0.5;")

    # ------------------------------------------------------------------ fila B: Lambdas de entrada y ECR
    cart = card(40, 290, 260, 100, "lambda", COMP, "Lambda Cart",
                "freshbox-procesar-carrito\nPOST · GET · DELETE del carrito", COMP, num=3)
    corder = card(360, 290, 290, 100, "lambda", COMP, "Lambda Create-Order",
                  "freshbox-crear-orden\nlee el carrito, calcula el total\ny publica la orden en SQS", COMP, num=4)
    edge(api, cart, "", SYNC + "exitX=0.296;exitY=1;entryX=0.5;entryY=0;", points=[[600, 250], [170, 250]])
    edge(api, corder, "", SYNC + "exitX=0.296;exitY=1;entryX=0.5;entryY=0;", points=[[600, 250], [505, 250]])
    vertex("/api/cart · GET · POST · DELETE", text(11, BLUE, "left", 1), 178, 258, 210, 18)
    vertex("/api/orders · POST", text(11, BLUE, "left", 1), 513, 258, 140, 18)

    ecr = card(860, 300, 250, 80, "ecr", COMP, "Amazon ECR", "4 repositorios freshbox-*\nimágenes linux/arm64\nescaneo al subir · últimas 10", COMP, isz=40)

    # ------------------------------------------------------------------ fila C: DynamoDB, SQS (+DLQ), Process-Order
    ddb = card(40, 460, 260, 100, "dynamodb", DB, "Amazon DynamoDB",
               "carrito-freshbox · on-demand\nPK userId · SK productId\nTTL expiresAt = 24 h", DB, num=6)
    sqs = card(500, 460, 280, 100, "sqs", INTEG, "Amazon SQS",
               "ordenes-freshbox · cifrada (SSE)\nentrega por lotes a Process-Order", INTEG, num=7)
    po = card(850, 460, 280, 100, "lambda", COMP, "Lambda Process-Order",
              "freshbox-procesar-orden\ntrigger SQS · INSERT en RDS\nENI en APP 1a y 1b (SG-LAMBDA)\nlotes de 10 · máx. 2 en paralelo", COMP, num=5,
              subnet=("PRIVADA APP", C_APP))
    dlq = card(575, 584, 210, 52, "sqs", INTEG, "DLQ", "ordenes-freshbox-dlq", INTEG, isz=32)

    edge(cart, ddb, "Put · Query\nDelete", SYNC + "exitX=0.5;exitY=1;entryX=0.5;entryY=0;")
    edge(corder, ddb, "", SYNC + "exitX=0.2;exitY=1;entryX=1;entryY=0.5;")
    vertex("Query carrito", text(11, BLUE, "left", 1), 312, 489, 100, 18)
    edge(corder, sqs, "", ASYNC + "exitX=0.8;exitY=1;entryX=0.3286;entryY=0;")
    vertex("SendMessage\n(asíncrono)", text(11, PURPLE, "left", 1), 600, 408, 110, 32)
    edge(sqs, po, "trigger\n(lotes)", ASYNC + "exitX=1;exitY=0.5;entryX=0;entryY=0.5;")
    edge(sqs, dlq, "", ASYNC + "exitX=0.643;exitY=1;entryX=0.5;entryY=0;")
    vertex("tras 3 intentos fallidos", text(10, PURPLE, "left", 1), 690, 563, 140, 16)

    # ------------------------------------------------------------------ VPC Endpoint Gateway (Process-Order -> DynamoDB)
    vpce = card(400, 660, 260, 80, "endpoints", NET, "VPC Endpoint Gateway",
                "DynamoDB · asociado a la RT APP\nsin salir a Internet · sin costo\npolítica: solo tabla carrito", NET, num=11, isz=44)
    edge(po, vpce, "", SYNC + "exitX=0.18;exitY=1;entryX=1;entryY=0.5;", points=[[900, 700]])
    vertex("borra el carrito · HTTPS 443", text(10, BLUE, "left", 1), 672, 680, 224, 16)
    edge(vpce, ddb, "", SYNC + "exitX=0;exitY=0.5;entryX=0.5;entryY=1;", points=[[170, 700]])
    vertex("acceso privado\npor la red de AWS", text(10, BLUE, "left", 1), 180, 600, 130, 30)

    # ------------------------------------------------------------------ columna derecha: EKS, RDS, CloudWatch y KMS
    ek_x, ek_y, ek_w, ek_h = 1180, 285, 290, 300
    eks = vertex("", box("#FFFFFF", COMP, DARK, extra="arcSize=3;strokeWidth=2;"), ek_x, ek_y, ek_w, ek_h)
    vertex("", icon("eks", COMP), ek_x + 12, ek_y + 8, 36, 36)
    vertex("<b>Amazon EKS · freshbox-cluster</b><br>Kubernetes 1.34 · 4 Deployments (CRUD)", text(12, DARK, "left", 0, "middle"),
           ek_x + 56, ek_y + 4, 228, 44)
    badge(9, ek_x - 12, ek_y - 12)
    chip("PRIVADA APP", C_APP, ek_x + ek_w - 112, ek_y - 9)
    vertex("", box("#FFF8F0", COMP, COMP, dashed=1, extra="dashPattern=8 4;strokeWidth=2;arcSize=4;"),
           ek_x + 12, ek_y + 56, ek_w - 24, 196)
    pods = [("get-products", "GET · :3001"), ("create-product", "POST · :3002"),
            ("update-product", "PUT · :3003"), ("delete-product", "DELETE · :3004")]
    for k, (nombre, metodo) in enumerate(pods):
        cx = ek_x + 12 + 66 + (k % 2) * 134
        py = ek_y + 68 + (k // 2) * 90
        vertex("", k8s_icon("pod"), cx - 20, py, 40, 40)
        vertex(f"{nombre}\n{metodo}", text(11, DARK, "center", 1), cx - 62, py + 42, 124, 32)
    vertex("2 réplicas por Deployment (1 por AZ) · HPA 2–5\nNode Group t4g.small 2–4 · EBS gp3 cifrado",
           text(10, "#5A6B7B", "center"), ek_x + 5, ek_y + 256, ek_w - 10, 32)

    edge(alb, eks, "", SYNC + "exitX=0.5;exitY=1;entryX=0.5;entryY=0;")
    vertex("HTTP :3001–3004", text(11, BLUE, "left", 1), 1333, 228, 130, 18)
    edge(ecr, eks, "pull de\nimágenes", SUP + "exitX=1;exitY=0.5;entryX=0;entryY=0.1833;")

    rds = card(1180, 640, 290, 100, "rds", DB, "Amazon RDS MySQL 8.0",
               "Multi-AZ · db.t4g.small · cifrada\nprimaria 1a · standby 1b\nproductos y órdenes\nrespaldo automático 7 días", DB, num=10,
               subnet=("PRIVADA DATA", C_DAT))
    edge(eks, rds, "", SYNC + "exitX=0.5;exitY=1;entryX=0.5;entryY=0;")
    vertex("MySQL 3306\n(pods CRUD)", text(11, BLUE, "left", 1), 1333, 590, 120, 32)
    edge(po, rds, "", SYNC + "exitX=0.786;exitY=1;entryX=0;entryY=0.5;", points=[[1070, 690]])
    vertex("INSERT orden\nMySQL 3306", text(11, BLUE, "left", 1), 1078, 580, 98, 32)

    card(1180, 756, 290, 58, "cloudwatch_2", MGMT, "Amazon CloudWatch",
         "logs de Lambda · Container Insights\nmétricas de API Gateway, RDS y SQS", MGMT, isz=36)
    card(1180, 824, 290, 58, "key_management_service", SEC, "AWS KMS",
         "aws/ebs (nodos) · aws/rds (base)\nSQS y DynamoDB: cifrado del servicio", SEC, isz=36)

    # ------------------------------------------------------------------ franja VPC (13): 2 AZ x 3 capas = 6 subredes
    VY, VH = 910, 290
    vertex("VPC freshbox-vpc · 10.0.0.0/22", group("group_vpc", "#3F8F29", "#FFFFFF", "#2E6B1E", fs=14), 20, VY, 1450, VH)
    badge(13, 8, VY - 12)
    igw = vertex("", icon("internet_gateway", NET), 488, 888, 40, 40)
    vertex("Internet Gateway", text(11, DARK, "left", 1), 534, 888, 150, 18)

    # cabecera de cada capa con su route table
    HY = 940
    capas = [(120, 380, pub, C_PUB, "Capa 1 · PÚBLICA — RT: 0.0.0.0/0 → Internet Gateway"),
             (515, 525, app, C_APP, "Capa 2 · PRIVADA APP — RT: 0.0.0.0/0 → NAT · DynamoDB → VPC Endpoint (11)"),
             (1055, 395, dat, C_DAT, "Capa 3 · PRIVADA DATA — RT: solo ruta local")]
    for x, w, p, c, t in capas:
        vertex("", box(p["fill"], c, p["text"], extra="arcSize=20;"), x, HY, w, 28)
        vertex("", icon("route_table", c), x + 6, HY + 3, 22, 22)
        vertex(t, text(11, p["text"], "left", 1, "middle"), x + 34, HY, w - 38, 28)

    # filas de AZ
    for ay, lab in ((975, "AZ1a\nus-east-1a"), (1085, "AZ1b\nus-east-1b")):
        vertex("", "rounded=0;whiteSpace=wrap;html=1;fillColor=none;strokeColor=#1F6FB2;dashed=1;dashPattern=8 4;strokeWidth=1.5;",
               30, ay, 1430, 100)
        vertex(lab, text(12, "#1F6FB2", "center", 1, "middle"), 34, ay, 82, 100)

    def subnet(titulo, p, x, y, w):
        return vertex(titulo, group("group_security_group", p["stroke"], p["fill"], p["text"], fs=12), x, y, w, 86)

    def sitem(res, fill, x, y, label, lw=180, align="left", extra=""):
        i = vertex("", icon(res, fill, extra), x, y, 36, 36)
        if align == "left":
            vertex(label, text(10, DARK, "left", 1, "middle"), x + 42, y - 4, lw, 44)
        else:
            vertex(label, text(10, DARK, "right", 1, "middle"), x - 6 - lw, y - 4, lw, 44)
        return i

    cidr = {"pub": ["10.0.0.0/25", "10.0.0.128/25"], "app": ["10.0.1.0/25", "10.0.1.128/25"],
            "dat": ["10.0.2.0/25", "10.0.2.128/25"]}
    pubs, nodes, rdss = [], [], []
    for k, sy in enumerate((982, 1092)):
        az = "1a" if k == 0 else "1b"
        iy = sy + 36
        pubs.append(subnet(f"Pública {az} · {cidr['pub'][k]}", pub, 120, sy, 380))
        subnet(f"Privada APP {az} · {cidr['app'][k]}", app, 515, sy, 525)
        subnet(f"Privada DATA {az} · {cidr['dat'][k]}", dat, 1055, sy, 395)
        sitem("application_load_balancer", NET, 140, iy, f"(8) ALB · nodo {az}", 150)
        nodes.append(sitem("ec2", COMP, 535, iy, "(9) Nodo EKS t4g.small\n4 pods CRUD", 200))
        sitem("lambda", COMP, 800, iy, "(5) ENI de Process-Order\n(SG-LAMBDA)", 196)
        if k == 0:
            rdss.append(sitem("rds", DB, 1075, iy, "(10) RDS primaria\nlectura y escritura", 220))
        else:
            rdss.append(sitem("rds", DB, 1075, iy, "(10) RDS standby\nsincrónica, sin tráfico", 220, extra="opacity=55;"))
    nat = sitem("nat_gateway", NET, 450, 1018, "NAT Gateway\n(único, en 1a)", 106, align="right")

    edge(igw, pubs[0], "", SYNC + f"exitX=0.5;exitY=1;entryX=1;entryY={(1000 - 982) / 86:.3f};", points=[[508, 1000]])
    edge(nodes[0], nat, "", SUP + "exitX=0;exitY=0.5;entryX=1;entryY=0.5;")
    edge(nodes[1], nat, "", SUP + "exitX=0;exitY=0.5;entryX=1;entryY=0.5;", points=[[508, 1146], [508, 1036]])
    edge(rdss[0], rdss[1], "",
         f"strokeColor={C_DAT};fontColor={C_DAT};fontStyle=1;fontSize=10;exitX=0.5;exitY=1;entryX=0.5;entryY=0;")
    vertex("replicación sincrónica (Multi-AZ)", text(10, C_DAT, "left", 1, "middle", bg="#FFFFFF"), 1102, 1072, 190, 16)

    # ------------------------------------------------------------------ Security Groups (12)
    GY = 1220
    vertex("", box("#FFFFFF", "#9AA5B1", DARK, extra="arcSize=3;"), 20, GY, 1450, 130)
    badge(12, 8, GY - 12)
    vertex("Security Groups (encadenados)", text(13, DARK, "left", 1), 40, GY + 6, 400, 22)
    sgs = [
        ("SG-ALB", "Entrada: 80/443 desde 0.0.0.0/0\nSalida: 3001–3004 → SG-EKS", "rojo", 40),
        ("SG-EKS", "Entrada: 3001–3004 solo desde SG-ALB\nSalida: 3306 → SG-RDS · 443 por NAT\nnodo ↔ nodo: SG del clúster", "azul", 400),
        ("SG-RDS", "Entrada: 3306 desde SG-EKS\ny SG-LAMBDA\nsin salida a Internet", "morado", 760),
        ("SG-LAMBDA", "Sin entrada\nSalida: 3306 → SG-RDS\n443 → DynamoDB (prefix list)", "naranja", 1120),
    ]
    sg_ids = []
    for nombre, regla, col, x in sgs:
        c = vertex("", box(PAL[col]["fill"], PAL[col]["stroke"], DARK, extra="arcSize=8;strokeWidth=2;"), x, GY + 34, 290, 86)
        vertex("", icon("shield", PAL[col]["stroke"]), x + 10, GY + 34 + 26, 34, 34)
        vertex(f"<b><font style=\"font-size:13px\">{nombre}</font></b><br>{regla}", text(11, DARK, "left", 0, "middle"),
               x + 52, GY + 36, 232, 82)
        sg_ids.append(c)
    edge(sg_ids[0], sg_ids[1], "3001–3004", SYNC + "exitX=1;exitY=0.5;entryX=0;entryY=0.5;")
    edge(sg_ids[1], sg_ids[2], "3306", SYNC + "exitX=1;exitY=0.5;entryX=0;entryY=0.5;")
    edge(sg_ids[3], sg_ids[2], "3306", SYNC + "exitX=0;exitY=0.5;entryX=1;entryY=0.5;")

    # ------------------------------------------------------------------ notas
    NY = 1370
    vertex("", box("#FFFFFF", "#9AA5B1", DARK, extra="arcSize=3;"), 20, NY, 1450, 126)
    vertex("NOTAS IMPORTANTES", text(13, DARK, "left", 1), 40, NY + 6, 300, 22)
    notas = [
        ("Escalabilidad", "Lambda escala por solicitud; HPA de 2 a 5 réplicas por Deployment al 70 % de CPU; Node Group de 2 a 4 nodos."),
        ("Desacoplamiento", "SQS separa la respuesta al cliente del registro en RDS; tras 3 intentos fallidos el mensaje pasa a la DLQ."),
        ("Seguridad", "SG encadenados por capa, RDS solo en subredes DATA, DynamoDB por VPC Endpoint, todo cifrado en reposo."),
        ("Alta disponibilidad", "ALB, nodos EKS y RDS en 2 AZ. El NAT es único (1a) por costo: si cae la AZ1a, APP 1b pierde la salida a Internet."),
        ("Lambda y la VPC", "solo Process-Order se conecta a la VPC (necesita RDS); Cart y Create-Order usan DynamoDB y SQS desde fuera."),
        ("API Gateway → ALB", "integración HTTP 80 por Internet (el lab no tiene certificado ACM); mejora propuesta: VPC Link con NLB."),
    ]
    for j, (nombre, det) in enumerate(notas):
        cx = 40 if j < 3 else 760
        y = NY + 32 + 30 * (j % 3)
        vertex(f"<b>{nombre}:</b> {det}", text(11, DARK, "left", 0, "middle"), cx, y, 690, 30)

    if sin_panel:  # solo la arquitectura: sin componentes, IAM, leyenda ni flujos
        return documento(W, H)

    # ------------------------------------------------------------------ panel 1: componentes 1 a 14 + soporte
    PX, PW = 1520, 460
    panel(PX, 20, PW, 482, "COMPONENTES DEL DISEÑO")
    comps = [
        "<b>Amazon S3</b> · sitio estático (HTML, CSS, JS)",
        "<b>API Gateway</b> · rutas a Lambda y al ALB",
        "<b>Lambda Cart</b> · CRUD del carrito en DynamoDB",
        "<b>Lambda Create-Order</b> · total y publicación en SQS",
        "<b>Lambda Process-Order</b> · consume SQS, escribe en RDS",
        "<b>DynamoDB</b> · tabla carrito con TTL de 24 h",
        "<b>SQS</b> · cola ordenes con DLQ",
        "<b>ALB Ingress</b> · lo crea EKS Auto Mode, regla por método",
        "<b>EKS</b> · 4 pods (GET, POST, PUT, DELETE)",
        "<b>RDS MySQL</b> · Multi-AZ (primaria 1a, standby 1b)",
        "<b>VPC Endpoint Gateway</b> · DynamoDB desde la VPC",
        "<b>Security Groups</b> · SG-ALB, SG-EKS, SG-RDS, SG-LAMBDA",
        "<b>VPC</b> · 6 subredes: pública, APP y DATA en 2 AZ",
        "<b>Flechas de flujo</b> · síncrono, asíncrono y soporte",
    ]
    for j, c in enumerate(comps):
        y = 58 + 29 * j
        badge(j + 1, PX + 14, y + 1)
        vertex(c, text(11, DARK, "left", 0, "middle"), PX + 52, y, PW - 60, 28)
        sep(PX + 10, y + 29, PW - 20)
    vertex("<b>Soporte</b> · Internet Gateway, NAT Gateway, ECR, CloudWatch y KMS",
           text(11, "#5A6B7B", "left", 0, "middle"), PX + 52, 58 + 29 * 14, PW - 60, 28)

    # ------------------------------------------------------------------ panel 2: IAM por Lambda
    IY, IH = 522, 304
    panel(PX, IY, PW, IH, "IAM ROLES POR LAMBDA")
    iam = [
        ("lambda", COMP, "Lambda\nCart", "dynamodb:PutItem\ndynamodb:Query\ndynamodb:DeleteItem", 56),
        ("lambda", COMP, "Lambda\nCreate-Order", "dynamodb:Query\nsqs:SendMessage", 44),
        ("lambda", COMP, "Lambda\nProcess-Order", "sqs:ReceiveMessage · sqs:DeleteMessage\nsqs:GetQueueAttributes\n"
         "dynamodb:Query · dynamodb:BatchWriteItem\nec2:Create/Describe/DeleteNetworkInterface", 70),
        ("cloudwatch_2", MGMT, "Las tres", "logs:CreateLogGroup · logs:CreateLogStream\nlogs:PutLogEvents", 44),
    ]
    y = IY + 38
    for res, fill, nombre, perms, h in iam:
        vertex("", icon(res, fill), PX + 14, y + (h - 30) / 2, 30, 30)
        vertex(nombre, text(11, DARK, "left", 1, "middle"), PX + 52, y, 100, h)
        vertex(perms, text(10, DARK, "left", 0, "middle"), PX + 156, y, PW - 164, h)
        y += h
        sep(PX + 10, y, PW - 20)
    vertex("<i>En el Learner Lab las tres funciones asumen LabRole (no se pueden crear roles IAM). "
           "Estas son las políticas mínimas del diseño objetivo.</i>", text(10, "#5A6B7B", "left", 0, "middle"),
           PX + 10, y + 2, PW - 20, 44)

    # ------------------------------------------------------------------ panel 3: leyenda de flechas (14)
    LY = IY + IH + 20
    panel(PX, LY, PW, 156, "FLECHAS DE FLUJO")
    badge(14, PX - 12, LY - 12)
    muestras = [
        (f"strokeColor={BLUE};", "<b>Flujo síncrono</b> (solicitud y respuesta)<br>Ej: Usuario → API Gateway → Lambda"),
        (f"strokeColor={PURPLE};dashed=1;dashPattern=8 4;", "<b>Flujo asíncrono</b> (desacoplado)<br>Ej: Create-Order → SQS → Process-Order"),
        (f"strokeColor={GREY};dashed=1;dashPattern=3 3;", "<b>Soporte</b> (imágenes y salida a Internet)<br>Ej: ECR → nodos EKS · nodos APP → NAT"),
    ]
    for j, (st, desc) in enumerate(muestras):
        yy = LY + 56 + 38 * j
        line(PX + 16, yy, PX + 86, yy, st)
        vertex(desc, text(11, DARK, "left", 0, "middle"), PX + 100, yy - 18, PW - 110, 36)

    # ------------------------------------------------------------------ panel 4: flujos de la pauta (2.3)
    FY = LY + 156 + 20
    panel(PX, FY, PW, 290, "FLUJOS DE LA APLICACIÓN")
    flujos = [
        ("Productos (CRUD)", "S3 → API Gateway → ALB → pod del método (GET, POST, PUT, DELETE) → RDS MySQL", "#D86613"),
        ("Carrito", "S3 → API Gateway → Lambda Cart → DynamoDB (el ítem expira a las 24 h por TTL)", "#1F6FB2"),
        ("Órdenes", "S3 → API Gateway → Create-Order → DynamoDB → SQS → Process-Order → RDS MySQL", "#7D3C98"),
        ("Confirmación", "Create-Order responde con orderId y total; el sitio muestra «Su pedido fue procesado». "
         "Process-Order guarda la orden y vacía el carrito", "#3F8F29"),
    ]
    y = FY + 40
    for nombre, det, col in flujos:
        h = 58
        vertex("", f"rounded=0;html=1;fillColor={col};strokeColor=none;", PX + 12, y + 4, 5, h - 8)
        vertex(f"<b>{nombre}</b><br>{det}", text(11, DARK, "left", 0, "middle"), PX + 26, y, PW - 36, h)
        y += h + 6

    return documento(W, H)


def documento(W, H):
    return (
        '<mxfile host="app.diagrams.net" agent="gen_d1_hibrido_tobe_v2" version="24.7.0">\n'
        '  <diagram id="tobe-hibrido-v2" name="D1 TO-BE híbrido v2">\n'
        '    <mxGraphModel dx="1600" dy="1000" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" '
        f'page="1" pageScale="1" pageWidth="{W}" pageHeight="{H}" math="0" shadow="0">\n'
        '      <root>\n        <mxCell id="0"/>\n        <mxCell id="1" parent="0"/>\n'
        + "\n".join("        " + c for c in cells)
        + "\n      </root>\n    </mxGraphModel>\n  </diagram>\n</mxfile>\n"
    )


if __name__ == "__main__":
    sin_panel = "--sin-panel" in sys.argv[1:]
    args = [a for a in sys.argv[1:] if a != "--sin-panel"]
    defecto = "D1_FreshBox_Hibrido_TOBE_v2_sin_panel.drawio" if sin_panel else "D1_FreshBox_Hibrido_TOBE_v2.drawio"
    out = args[0] if args else defecto
    with open(out, "w", encoding="utf-8") as f:
        f.write(build(sin_panel))
    print(f"OK {out} ({len(cells)} celdas)")
