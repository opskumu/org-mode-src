#!/usr/bin/env python3
"""Rebuild the article's SVG sources and PNGs (requires rsvg-convert)."""

from html import escape
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "images"
INK, MUTED, LINE = "#24313a", "#586971", "#aabbbf"
BLUE, BLUE_BG, WARM_BG = "#3b6d88", "#e9f1f5", "#f5eee8"


class Figure:
    def __init__(self, height, title, subtitle):
        self.height = height
        self.parts = [
            f'<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="{height}" viewBox="0 0 1200 {height}" role="img">',
            f'<title>{escape(title)}</title><desc>{escape(subtitle)}</desc>',
            '<defs><marker id="arrow" markerWidth="10" markerHeight="10" refX="8" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8" fill="#3b6d88"/></marker></defs>',
            '<rect width="1200" height="100%" fill="#fff"/>',
            '<g font-family="PingFang SC,Noto Sans CJK SC,Arial,sans-serif">',
        ]
        self.text(60, 60, title, 34, weight=600)
        self.text(60, 103, subtitle, 22, color=MUTED)

    def text(self, x, y, value, size=26, color=INK, anchor="start", weight=400):
        self.parts.append(f'<text x="{x}" y="{y}" font-size="{size}" fill="{color}" text-anchor="{anchor}" font-weight="{weight}">{escape(value)}</text>')

    def rect(self, x, y, w, h, fill=BLUE_BG, stroke="none", radius=12):
        self.parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" fill="{fill}" stroke="{stroke}"/>')

    def node(self, x, y, w, h, title, note="", fill=BLUE_BG):
        self.rect(x, y, w, h, fill)
        self.text(x+w/2, y+(h/2+9 if not note else h/2-4), title, 27, anchor="middle", weight=500)
        if note:
            self.text(x+w/2, y+h/2+27, note, 21, color=MUTED, anchor="middle")

    def path(self, d, arrow=True, color=BLUE):
        self.parts.append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="2.5" stroke-linejoin="round"'+(' marker-end="url(#arrow)"' if arrow else '')+'/>')

    def plus(self, x, y):
        self.parts.append(f'<circle cx="{x}" cy="{y}" r="24" fill="#fff" stroke="{BLUE}" stroke-width="2.5"/>')
        self.text(x, y+10, "+", 32, anchor="middle")

    def save(self, name):
        svg = OUT / (name + ".svg")
        svg.write_text("\n".join(self.parts + ["</g></svg>"]) + "\n")
        subprocess.run(["rsvg-convert", str(svg), "-o", str(OUT / (name + ".png"))], check=True)


def pipeline():
    f = Figure(850, "大语言模型：从文字到下一个 token", "一次生成结束后，新 token 加入上下文，继续下一轮")
    labels = [
        ("文字输入", "提示词与已有对话"),
        ("Tokenizer", "文字 → token ID 序列"),
        ("Embedding 与位置机制", "ID → 向量，并使模型能够利用顺序"),
        ("多层 Transformer", "注意力 + MLP + 残差 + 归一化"),
        ("词表输出投影", "为词表中的每个候选输出 logit"),
        ("Softmax 与解码选择", "概率分布 → 选中下一个 token"),
    ]
    for i, (title, note) in enumerate(labels):
        y = 145+i*104
        f.node(140, y, 650, 78, title, note)
        if i < 5:
            f.path(f"M465,{y+78} V{y+101}")
    f.path("M790,704 H1050 V340 H465")
    f.text(935, 470, "追加到上下文", 24, anchor="middle")
    f.text(935, 508, "复用固定模型参数", 21, color=MUTED, anchor="middle")
    f.text(60, 809, "表示方式、网络计算、解码选择是三个不同层次。", 22, color=MUTED)
    f.save("llm-pipeline")


def attention():
    f = Figure(900, "注意力：先决定读取比例，再汇总内容", "单头示意；数值与向量为教学构造，非模型测量结果")
    f.node(330, 145, 540, 65, "输入表示 H")
    f.path("M600,210 V232 H215 V255")
    f.path("M600,210 V255")
    f.path("M600,232 H985 V255")
    for x, title, note in [(75,"Q：当前需要什么","H × WQ"),(460,"K：如何匹配","H × WK"),(845,"V：汇入什么内容","H × WV")]:
        f.node(x, 260, 280, 90, title, note)
    f.path("M215,350 V385 H405 V410")
    f.path("M600,350 V385 H405")
    f.node(75, 415, 665, 85, "点积打分、缩放、因果遮罩", "QKᵀ / sqrt(d_k) + M")
    f.path("M405,500 V535")
    f.node(75, 540, 665, 85, "Softmax → 位置权重", "示例：[0.2, 0.3, 0.5]")
    f.path("M405,625 V665")
    f.path("M985,350 V707 H920")
    f.node(75, 670, 850, 90, "对 Value 加权求和", "output = 0.2 v₁ + 0.3 v₂ + 0.5 v₃", WARM_BG)
    f.text(60, 815, "若 v₁=[1,0]，v₂=[0,2]，v₃=[2,2]，则 output=[1.2,1.6]。", 25)
    f.text(60, 859, "注意力中的 Softmax 面向上下文位置；最终输出的 Softmax 面向词表。", 22, color=MUTED)
    f.save("llm-attention")


def training():
    f = Figure(900, "因果依赖不等于训练必须串行", "每个位置只能读取自己与过去，用来预测下一个位置")
    f.text(65, 169, "因果遮罩：行读取列", 27, weight=500)
    step, x0, y0 = 70, 130, 240
    for i in range(5):
        f.text(x0+i*step+30, y0-20, str(i+1), 24, anchor="middle")
        f.text(96, y0+i*step+40, str(i+1), 24, anchor="middle")
        for j in range(5):
            f.rect(x0+j*step, y0+i*step, 60, 60, BLUE_BG if j<=i else "#f1f2f2", radius=5)
            f.text(x0+j*step+30, y0+i*step+40, "可见" if j<=i else "—", 22, color=INK if j<=i else MUTED, anchor="middle")
    f.text(65, 630, "上三角的未来位置被屏蔽", 23, color=MUTED)
    f.text(65, 667, "对应注意力权重为 0", 23, color=MUTED)
    f.text(620, 169, "训练：真实文本已经存在", 27, weight=500)
    for y, a, b in [(215,"<开始>","我"),(295,"我","喜欢"),(375,"喜欢","学习"),(455,"学习","<结束>")]:
        f.node(620,y,160,58,a)
        f.path(f"M790,{y+29} H908")
        f.node(920,y,210,58,b,fill=WARM_BG)
    f.text(790, 556, "遮罩约束下，可并行算多个位置", 23, color=MUTED, anchor="middle")
    f.text(620, 627, "生成：后续 token 尚未确定", 27, weight=500)
    f.text(620, 675, "我 → 我 喜欢 → 我 喜欢 学习", 25)
    f.text(620, 721, "常规解码逐步扩展前缀", 23, color=MUTED)
    f.rect(60, 776, 1080, 76, WARM_BG)
    f.text(600, 808, "训练用真实前缀；生成用已经选出的前缀。", 25, anchor="middle")
    f.text(600, 839, "中文按词展示，仅说明输入与目标的移位关系。", 21, color=MUTED, anchor="middle")
    f.save("llm-training-generation")


def block():
    f = Figure(900, "一个常见的 Pre-norm Transformer Block", "跨位置汇总信息，再逐位置做非线性变换；残差路径保留已有表示")
    f.text(620, 157, "输入 h：[n, d]", 27, anchor="middle")
    f.path("M620,170 V205")
    f.path("M620,180 H230 V425 H588")
    f.node(370, 210, 500, 64, "Norm")
    f.path("M620,274 V302")
    f.node(370, 307, 500, 75, "因果多头注意力", "跨位置汇总信息")
    f.path("M620,382 V396")
    f.plus(620,425)
    f.text(145, 310, "残差", 24)
    f.text(920, 432, "u = h + Attention(Norm(h))", 20, anchor="middle")
    f.path("M620,449 V482")
    f.path("M620,460 H230 V700 H588")
    f.node(370, 487, 500, 64, "Norm")
    f.path("M620,551 V577")
    f.node(370, 582, 500, 75, "MLP / 前馈网络", "共享参数，逐位置加工")
    f.path("M620,657 V671")
    f.plus(620,700)
    f.text(145, 600, "残差", 24)
    f.text(930, 707, "y = u + MLP(Norm(u))", 20, anchor="middle")
    f.path("M620,724 V770")
    f.text(620, 811, "输出 y：[n, d] → 下一层", 27, anchor="middle")
    f.text(60, 861, "图示为一种结构；归一化顺序、激活函数、注意力与位置机制因模型而异。", 22, color=MUTED)
    f.save("llm-transformer-block")


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    for draw in [pipeline, attention, training, block]:
        draw()
