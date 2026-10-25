#!/usr/bin/env python3
"""
D1 - Arquitectura TO-BE de FreshBox SpA con Amazon EKS + RDS MySQL Multi-AZ (EP2).

Misma composición que el D1 de EP1 (EV1/diagramas): rótulos de capa a la izquierda,
dos AZ en columnas punteadas, ALB centrado entre AZ, cajas de SG y flujo al pie.
Cambia la capa APP (clúster EKS, Managed Node Group t4g.small 2-4, 5 pods por zona y
HPA) y la capa DATA (RDS primaria en AZ1a + standby en AZ1b, snapshots automáticos).
Los servicios regionales (Ingress Controller de EKS Auto Mode, plano de control, ECR,
Container Insights, KMS) van en una columna fuera de la VPC.

Valores de la pauta EP2: VPC /22, Node Group t4g.small 2-4, RDS db.t4g.small Multi-AZ,
SG-ALB 80/443 desde 0.0.0.0/0, SG-EKS 80/443 desde SG-ALB, SG-RDS 3306 desde SG-EKS.
La red reutiliza los CIDR de EV1; la capa DATA pierde la ruta al NAT.

Uso:  python gen_d1_eks_tobe.py D1_FreshBox_EKS_TOBE.drawio
"""
import sys
from xml.sax.saxutils import escape

PAL = {
    "verde":  {"fill": "#E9F3DF", "stroke": "#3F8F29", "text": "#2E6B1E"},
    "azul":   {"fill": "#E6F0FA", "stroke": "#1F6FB2", "text": "#0B4F79"},
    "morado": {"fill": "#EFE6F7", "stroke": "#7D3C98", "text": "#5A2D82"},
    "rojo":   {"fill": "#FDECEE", "stroke": "#DD344C", "text": "#7D0000"},
    "naranja": {"fill": "#FFF3E0", "stroke": "#D86613", "text": "#7A3A00"},
}
DARK, NET, COMP, DB, K8S, MGMT, SEC = "#16324F", "#8C4FFF", "#ED7100", "#C925D1", "#326CE5", "#E7157B", "#DD344C"

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


def edge(src, dst, label="", style="", points=None, lx=None):
    i = nid()
    base = ("edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;fontSize=11;fontColor=#232F3E;endArrow=block;"
            "endFill=1;strokeWidth=2;strokeColor=#232F3E;labelBackgroundColor=#FFFFFF;")
    pts = ""
    if points:
        pts = '<Array as="points">' + "".join(f'<mxPoint x="{px}" y="{py}"/>' for px, py in points) + "</Array>"
    gx = f' x="{lx}"' if lx is not None else ""
    cells.append(f'<mxCell id="{i}" value="{_val(label)}" style="{base}{style}" edge="1" parent="1" source="{src}" target="{dst}">'
                 f'<mxGeometry relative="1"{gx} as="geometry">{pts}</mxGeometry></mxCell>')
    return i


def icon(res, fill, label_pos="bottom", extra=""):
    va = "top" if label_pos == "bottom" else "bottom"
    return ("sketch=0;outlineConnect=0;fontColor=#232F3E;gradientColor=none;"
            f"fillColor={fill};strokeColor=none;dashed=0;verticalLabelPosition={label_pos};"
            f"verticalAlign={va};align=center;html=1;fontSize=12;fontStyle=1;aspect=fixed;"
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


def build():
    W, H = 1610, 1390
    pub, app, dat = PAL["verde"], PAL["azul"], PAL["morado"]
    AZX, AZW = [210, 760], 470
    CX = 720  # eje central entre AZ

    # --- título ---
    vertex("Arquitectura TO-BE de FreshBox SpA con Amazon EKS y RDS Multi-AZ", text(24, DARK, "center", 1), 0, 8, W, 36)
    vertex("AWS · Orquestación de contenedores (Amazon EKS) + PaaS (RDS MySQL Multi-AZ) · 3 capas en 2 zonas · Región us-east-1",
           text(15, "#1F3A5F", "center"), 0, 46, W, 24)

    # --- fila superior ---
    users = vertex("Usuarios\n(Internet)", icon("users", "#232F3E"), 70, 105, 56, 56)
    inet = vertex("Internet", "ellipse;shape=cloud;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#232F3E;"
                  "strokeWidth=2;fontSize=13;fontStyle=1;fontColor=#232F3E;", 215, 90, 160, 90)
    igw = vertex("Internet Gateway\n(freshbox-igw)",
                 icon("internet_gateway", NET, extra="labelPosition=right;verticalLabelPosition=middle;align=left;verticalAlign=middle;spacingLeft=6;"),
                 CX - 31, 104, 62, 62)
    edge(users, inet, "", "exitX=1;exitY=0.5;entryX=0;entryY=0.5;")
    edge(inet, igw, "HTTP 80 / HTTPS 443", "exitX=1;exitY=0.5;entryX=0;entryY=0.5;")

    # --- capas: posiciones verticales ---
    Y1, H1 = 305, 160   # pública
    Y2, H2 = 490, 380   # privada APP
    Y3, H3 = 895, 190   # privada DATA
    vpc_y, vpc_h = 230, Y3 + H3 + 30 - 230
    az_y, az_h = 262, Y3 + H3 + 15 - 262

    # --- VPC y AZ ---
    vertex("VPC freshbox-vpc 10.0.0.0/22", group("group_vpc", "#3F8F29", "#FFFFFF", "#2E6B1E", fs=15), 20, vpc_y, 1230, vpc_h)
    for k, lab in enumerate(["AZ1a (us-east-1a)", "AZ1b (us-east-1b)"]):
        vertex(lab, "rounded=0;whiteSpace=wrap;html=1;fillColor=none;strokeColor=#1F6FB2;dashed=1;dashPattern=8 4;"
               "fontSize=15;fontStyle=1;align=center;verticalAlign=top;spacing=6;fontColor=#1F6FB2;strokeWidth=2;",
               AZX[k], az_y, AZW, az_h)

    # --- rótulos de capa (izquierda), con la ruta por defecto de cada capa ---
    vertex("Capa 1\nPÚBLICA\n\nRT pública:\n0.0.0.0/0 → IGW", box(pub["fill"], "none", pub["text"], fs=13, valign="middle"), 30, Y1, 170, H1)
    vertex("Capa 2\nPRIVADA APP\n\nRT privada APP:\n0.0.0.0/0 → NAT GW\n(único, en pública 1a)", box(app["fill"], "none", app["text"], fs=13, valign="middle"), 30, Y2, 170, H2)
    vertex("Capa 3\nPRIVADA DATA\n\nRT data: solo ruta\nlocal (sin Internet)", box(dat["fill"], "none", dat["text"], fs=13, valign="middle"), 30, Y3, 170, H3)

    # --- subredes ---
    def subnet(nombre, cidr, pal, k, y, h):
        return vertex(f"{nombre}\n{cidr}", group("group_security_group", pal["stroke"], pal["fill"], pal["text"]),
                      AZX[k] + 10, y, AZW - 20, h)

    subnet("Subred pública 1a", "10.0.0.0/25", pub, 0, Y1, H1)
    subnet("Subred pública 1b", "10.0.0.128/25", pub, 1, Y1, H1)
    subnet("Subred privada APP 1a", "10.0.1.0/25", app, 0, Y2, H2)
    subnet("Subred privada APP 1b", "10.0.1.128/25", app, 1, Y2, H2)
    subnet("Subred privada DATA 1a", "10.0.2.0/25", dat, 0, Y3, H3)
    subnet("Subred privada DATA 1b", "10.0.2.128/25", dat, 1, Y3, H3)

    # --- Capa 1: ALB (Ingress) centrado + un NAT único en la pública 1a ---
    alb_y = 326
    alb = vertex("", icon("application_load_balancer", NET), CX - 31, alb_y, 62, 62)
    vertex("ALB · Ingress freshbox-ingress (SG-ALB)", text(13, DARK, "center", 1, bg=pub["fill"]), CX - 160, alb_y + 66, 320, 20)
    vertex("internet-facing · listener HTTP:80 (HTTPS:443 con certificado ACM) · target-type ip",
           text(10, "#5A6B7B", "center", bg=pub["fill"]), CX - 200, alb_y + 86, 400, 30)
    edge(igw, alb, "", "exitX=0.5;exitY=1;entryX=0.5;entryY=0;")
    vertex("", icon("nat_gateway", NET), 300, 382, 46, 46)
    vertex("NAT Gateway freshbox-natgw\nsalida de las 2 subredes APP", text(11, DARK, "center", 1), 218, 430, 210, 32)

    # --- Capa 2: clúster EKS > Managed Node Group > nodos > pods; HPA en el eje ---
    eks_y, eks_h = 540, 312
    eks_box = vertex("", box("none", "#D86613", "#D86613", rounded=0, extra="strokeWidth=2;"), 232, eks_y, 976, eks_h)
    vertex("", icon("eks", COMP), CX - 23, eks_y - 23, 46, 46)
    vertex("Clúster Amazon EKS freshbox-cluster (Kubernetes 1.34) · namespace freshbox",
           text(13, "#D86613", "center", 1, bg=app["fill"]), CX - 300, eks_y + 26, 600, 20)

    ng_y, ng_h = 610, 232
    vertex("", box("none", "#D86613", "#D86613", dashed=1, rounded=0, extra="dashPattern=8 4;strokeWidth=2;"), 240, ng_y, 960, ng_h)
    vertex("", icon("auto_scaling2", COMP), CX - 18, ng_y - 18, 36, 36)
    vertex("Managed Node Group freshbox-ng · Auto Scaling de 2 a 4 nodos", text(13, "#D86613", "center", 1, bg=app["fill"]), CX - 300, ng_y + 20, 600, 18)
    vertex("t4g.small Graviton (arm64) · mín 2 / máx 4 · EBS gp3 cifrado",
           text(10, "#7A3A00", "center", bg=app["fill"]), CX - 250, ng_y + 38, 500, 16)

    pods = [("get-products", ":3001"), ("create-product", ":3002"), ("frontend", ":80"),
            ("update-product", ":3003"), ("delete-product", ":3004")]
    NODEX, NODEW, NODEY, NODEH = [245, 785], 410, 672, 160
    nodes, front = [], []
    for k in range(2):
        nx = NODEX[k]
        n = vertex("", box("#FFFFFF", "#ED7100", DARK, rounded=1, extra="arcSize=4;"), nx, NODEY, NODEW, NODEH)
        nodes.append(n)
        vertex("", icon("ec2", COMP), nx + 10, NODEY + 8, 28, 28)
        vertex(f"Nodos EC2 · AZ{'1a' if k == 0 else '1b'}", text(12, DARK, "left", 1), nx + 44, NODEY + 12, 220, 18)
        for j, (p, port) in enumerate(pods):
            px = nx + 18 + 78 * j
            pid = vertex("", k8s_icon("pod"), px + 3, NODEY + 44, 36, 36)
            vertex(f"{p}\n{port}", text(10, DARK, "center", 1), px - 18, NODEY + 82, 78, 28)
            if p == "frontend":
                front.append(pid)
        vertex("1 réplica de cada Deployment por zona (2 por servicio = 10 pods)\nNginx (frontend) → Services ClusterIP por DNS interno",
               text(10, "#5A6B7B", "center"), nx + 5, NODEY + 116, NODEW - 10, 32)

    # HPA en el eje central, apuntando a los Deployments de ambos nodos
    hpa = vertex("", k8s_icon("hpa"), CX - 23, 700, 46, 46)
    vertex("HPA ×5\n(uno por\nDeployment)\n2–5 · CPU 70 %", text(11, K8S, "center", 1), CX - 60, 748, 120, 64)
    edge(hpa, nodes[0], "", "dashed=1;strokeColor=#326CE5;exitX=0;exitY=0.5;entryX=1;entryY=0.33;")
    edge(hpa, nodes[1], "", "dashed=1;strokeColor=#326CE5;exitX=1;exitY=0.5;entryX=0;entryY=0.33;")

    # ALB -> pod frontend de cada AZ (sale por los costados del ALB)
    for k in range(2):
        fx = NODEX[k] + 18 + 78 * 2 + 21
        edge(alb, front[k], "HTTP 80", f"exitX={k};exitY=0.5;entryX=0.5;entryY=0;", points=[[fx, alb_y + 31]])

    # --- Capa 3: RDS MySQL Multi-AZ + snapshots automáticos ---
    rds_y = 935
    PX, SX = 481, 961  # x de los íconos de la primaria y del standby
    prim = vertex("", icon("rds", DB), PX, rds_y, 58, 58)
    vertex("RDS MySQL 8.0 · Primaria (freshbox-db)\ndb.t4g.small · cifrada (KMS) · sin acceso público", text(12, DARK, "center", 1), PX - 120, rds_y + 62, 300, 34)
    stby = vertex("", icon("rds", DB, extra="opacity=55;"), SX, rds_y, 58, 58)
    vertex("RDS Standby (Multi-AZ de instancia)\nsincrónico; no atiende lecturas", text(12, DARK, "center", 1), SX - 121, rds_y + 62, 300, 34)
    edge(prim, stby, "Replicación sincrónica · failover\nautomático con el mismo endpoint", "dashed=1;exitX=1;exitY=0.5;entryX=0;entryY=0.5;")
    snap = vertex("", icon("backup_restore", DB), 270, rds_y + 8, 42, 42)
    vertex("Snapshots automáticos\n(retención 7 días)", text(10, DARK, "center", 1), 226, rds_y + 54, 130, 30)
    edge(prim, snap, "", "dashed=1;exitX=0;exitY=0.5;entryX=1;entryY=0.5;")

    # nodos -> RDS primaria (MySQL 3306)
    x1 = PX + 58 * 0.25
    edge(nodes[0], prim, "MySQL 3306", f"exitX={(x1 - NODEX[0]) / NODEW:.3f};exitY=1;entryX=0.25;entryY=0;", lx=0.5)
    edge(nodes[1], prim, "MySQL 3306", "exitX=0.5;exitY=1;entryX=0.75;entryY=0;",
         points=[[NODEX[1] + NODEW / 2, Y2 + H2 + 13], [PX + 58 * 0.75, Y2 + H2 + 13]], lx=-0.3)

    # --- servicios administrados (fuera de la VPC) ---
    RX, RW = 1275, 320
    col_y = 290
    vertex("Servicios administrados por AWS\n(regionales, fuera de la VPC)", box("#FAFAFA", "#9E9E9E", DARK, fs=13, dashed=1, align="center"),
           RX, col_y, RW, 740)

    def svc(res, fill, titulo, detalle, y, h=88):
        b = vertex("", box("#FFFFFF", "#BDBDBD", DARK, rounded=1), RX + 12, y, RW - 24, h)
        vertex("", icon(res, fill), RX + 22, y + (h - 44) / 2, 44, 44)
        vertex(f"<b>{titulo}</b><br>{detalle}", text(11, DARK, "left", 0, "middle"), RX + 74, y + 4, RW - 92, h - 8)
        return b

    ictl = svc("elastic_load_balancing", NET, "Ingress Controller (EKS Auto Mode)",
               "lee el Ingress freshbox-ingress y crea el ALB, sus listeners y target groups", 345)
    vertex("Los nodos llegan a estos servicios por HTTPS 443, saliendo por el NAT GW (flechas punteadas).",
           text(11, "#5A6B7B", "left"), RX + 16, 455, RW - 32, 60)
    cp = svc("eks", COMP, "Amazon EKS · plano de control",
             "administrado por AWS · Kubernetes 1.34 · API con autenticación IAM · roles LabEksClusterRole y LabEksNodeRole", 560)
    ecr = svc("ecr", COMP, "Amazon ECR · 5 repositorios",
              "freshbox-frontend, -get-products, -create-product, -update-product, -delete-product (linux/arm64)", 660)
    cw = svc("cloudwatch_2", MGMT, "CloudWatch Container Insights",
             "add-on amazon-cloudwatch-observability: métricas y logs de nodos, pods y contenedores", 760)
    kms = svc("key_management_service", SEC, "AWS KMS",
              "claves aws/ebs y aws/rds: cifrado en reposo de los nodos y de la base de datos", rds_y - 15)
    for tgt, ey in ((cp, (604 - eks_y) / eks_h), (ecr, (704 - eks_y) / eks_h), (cw, (804 - eks_y) / eks_h)):
        edge(eks_box, tgt, "", f"dashed=1;exitX=1;exitY={ey:.3f};entryX=0;entryY=0.5;")
    edge(stby, kms, "cifrado en reposo", "dashed=1;exitX=1;exitY=0.5;entryX=0;entryY=0.5;")

    # Ingress Controller -> ALB: sube por el borde de la VPC y entra al ALB por arriba
    edge(ictl, alb, "", "dashed=1;strokeColor=#8C4FFF;exitX=0;exitY=0.5;entryX=0.82;entryY=0;",
         points=[[1262, 389], [1262, 200], [740, 200]])
    vertex("crea y actualiza el ALB a partir del Ingress", text(11, "#5B2FB0", "right", 1), 900, 176, 350, 18)

    # --- pie: Security Groups (matriz de la pauta 2.4) ---
    by = Y3 + H3 + 55
    sgs = [("SG-ALB", "80/443 desde 0.0.0.0/0 (Internet)", "rojo"),
           ("SG-EKS", "80/443 desde SG-ALB (ALB → pods); tráfico interno del clúster por el SG del clúster", "azul"),
           ("SG-RDS", "3306 desde SG-EKS (solo los pods del clúster)", "morado")]
    vertex("Security Groups (SG)", box("#FFFFFF", "#9E9E9E", DARK, fs=14, dashed=1), 20, by, 460, 40 + 46 * len(sgs))
    for j, (nm, regla, col) in enumerate(sgs):
        y = by + 42 + 46 * j
        vertex("", icon("shield", PAL[col]["stroke"]), 36, y, 34, 34)
        vertex(nm, text(13, DARK, "left", 1), 80, y + 8, 80, 20)
        vertex(regla, text(12, DARK, "left"), 160, y + 1, 312, 36)

    # --- pie: flujo numerado ---
    flujo = [
        "Usuario → Internet → IGW → ALB :80/443 (SG-ALB)",
        "ALB → pod frontend (Nginx :80) en AZ1a o AZ1b, target-type ip (SG-EKS)",
        "Nginx enruta /api/products por método HTTP a los Services ClusterIP :3001–3004",
        "Microservicio → RDS primaria :3306 (SG-RDS); replicación sincrónica al standby",
        "Los nodos descargan las imágenes arm64 desde ECR por el NAT GW (HTTPS 443)",
        "Container Insights recoge métricas; Metrics Server alimenta el HPA (2–5 réplicas)",
    ]
    colores = ["#1F6FB2", "#3F8F29", "#7D3C98", "#DD344C", "#D86613", "#147EBA"]
    vertex("Flujo de la aplicación", box("#FFFFFF", "#9E9E9E", DARK, fs=14, dashed=1), 495, by, 600, 40 + 30 * len(flujo))
    for j, f in enumerate(flujo):
        y = by + 40 + 30 * j
        vertex(str(j + 1), f"ellipse;whiteSpace=wrap;html=1;fillColor={colores[j]};strokeColor=none;"
               "fontColor=#FFFFFF;fontSize=11;fontStyle=1;align=center;verticalAlign=middle;", 512, y, 22, 22)
        vertex(f, text(12, DARK, "left"), 542, y + 2, 545, 24)

    # --- pie: mecanismos de escalabilidad, seguridad y HA ---
    mec = [("Escalabilidad", "HPA en los 5 Deployments (2–5 réplicas, CPU 70 %) y Node Group de 2 a 4 nodos t4g.small", "naranja"),
           ("Seguridad", "Pods y RDS en subredes privadas, SG encadenados ALB → EKS → RDS, EBS y RDS cifrados con KMS", "rojo"),
           ("Alta disponibilidad", "Nodos y réplicas en 2 AZ, ALB en 2 subredes, RDS Multi-AZ con failover y snapshots diarios", "verde")]
    vertex("Mecanismos integrados", box("#FFFFFF", "#9E9E9E", DARK, fs=14, dashed=1), 1110, by, 485, 40 + 58 * len(mec))
    for j, (nm, det, col) in enumerate(mec):
        y = by + 40 + 58 * j
        vertex(nm, box(PAL[col]["fill"], "none", PAL[col]["text"], fs=12, align="center", valign="middle"), 1124, y, 128, 48)
        vertex(det, text(11, DARK, "left", 0, "middle"), 1260, y, 328, 48)

    return (
        '<mxfile host="app.diagrams.net" agent="gen_d1_eks_tobe" version="24.7.0">\n'
        '  <diagram id="tobe-eks" name="D1 TO-BE EKS">\n'
        '    <mxGraphModel dx="1600" dy="1000" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" '
        f'page="1" pageScale="1" pageWidth="{W}" pageHeight="{H}" math="0" shadow="0">\n'
        '      <root>\n        <mxCell id="0"/>\n        <mxCell id="1" parent="0"/>\n'
        + "\n".join("        " + c for c in cells)
        + "\n      </root>\n    </mxGraphModel>\n  </diagram>\n</mxfile>\n"
    )


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "D1_FreshBox_EKS_TOBE.drawio"
    with open(out, "w", encoding="utf-8") as f:
        f.write(build())
    print(f"OK {out} ({len(cells)} celdas)")
