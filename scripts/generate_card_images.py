# -*- coding: utf-8 -*-
"""
生成示例卡牌图片（占位卡图，可重复运行覆盖）
输出：public/images/cards/{card_id}.png（512x512），共 60 张
用法：python scripts/generate_card_images.py
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "public", "images", "cards")
SIZE = 512
FONT_BOLD = r"C:\Windows\Fonts\msyhbd.ttc"
FONT_REG = r"C:\Windows\Fonts\msyh.ttc"

GOLD = (255, 217, 122)
GOLD_DARK = (184, 134, 11)
WHITE = (245, 245, 245)

# 种类配置：key -> (卡名前缀, 主题色1, 主题色2, 图标类型, 短标签)
CATEGORIES = {
    "elixir":       ("e", (123, 79, 191), (34, 14, 64), "droplet", "圣水"),
    "dark_elixir":  ("d", (58, 48, 110), (12, 8, 30), "dark_droplet", "暗黑重油"),
    "builder_base": ("b", (211, 84, 0), (74, 34, 4), "wrench", "建筑大师"),
    "super_troop":  ("s", (214, 69, 65), (88, 14, 16), "sparkle", "超级兵种"),
}

CARD_NAMES = {
    "elixir": ["野蛮人", "弓箭手", "巨人", "哥布林", "炸弹人", "气球兵", "法师", "天使", "飞龙", "皮卡超人", "飞龙宝宝", "掘地矿工", "雷电飞龙", "大雪怪", "龙骑士", "雷霆泰坦", "根蔓骑士", "巨矛投手", "陨石戈仑"],
    "dark_elixir": ["亡灵", "野猪骑士", "瓦基里丽武神", "戈仑石人", "女巫", "熔岩猎犬", "巨石投手", "戈仑冰人", "英雄猎手", "守护者学徒", "德鲁伊", "烈焰熔炉", "废墟女巫"],
    "builder_base": ["狂暴野蛮人", "隐秘弓箭手", "巨人拳击手", "异变亡灵", "炸弹兵", "飞龙宝宝", "加农炮战车", "暗夜女巫", "骷髅气球", "雷霆皮卡", "野猪飞骑"],
    "super_troop": ["超级野蛮人", "超级弓箭手", "超级巨人", "隐秘哥布林", "超级炸弹人", "火箭气球兵", "超级法师", "超级飞龙", "地狱飞龙", "超级矿工", "超级大雪怪", "超级亡灵", "超级野猪骑士", "超级瓦基丽武神", "超级女巫", "寒冰猎犬", "超级巨石投手"],
}


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def vertical_gradient(c1, c2, w=SIZE, h=SIZE):
    small = Image.new("RGB", (1, 256))
    d = ImageDraw.Draw(small)
    for y in range(256):
        d.line([(0, y), (0, y)], fill=lerp(c1, c2, y / 255))
    return small.resize((w, h), Image.BILINEAR)


def radial_overlay(size, center, radius, color, max_alpha, dark=False):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    steps = 60
    for i in range(steps, 0, -1):
        r = radius * i / steps
        t = i / steps
        alpha = int(max_alpha * (1 - t)) if not dark else int(max_alpha * t)
        bbox = [center[0] - r, center[1] - r, center[0] + r, center[1] + r]
        d.ellipse(bbox, fill=(*color, alpha))
    return layer


def draw_emblem(d, cx, cy, kind):
    g = GOLD
    gd = GOLD_DARK
    L = 8

    def poly(pts):
        d.polygon(pts, fill=g, outline=gd)
        d.line(pts + [pts[0]], fill=gd, width=4)

    if kind == "droplet":  # 圣水：水滴
        d.ellipse([cx - 62, cy - 10, cx + 62, cy + 90], fill=g, outline=gd, width=4)
        poly([(cx - 60, cy - 5), (cx, cy - 105), (cx + 60, cy - 5)])
        d.ellipse([cx - 26, cy + 22, cx + 4, cy + 52], fill=(255, 255, 255, 130))
    elif kind == "dark_droplet":  # 暗黑重油：水滴 + 光环
        d.ellipse([cx - 55, cy - 30, cx + 55, cy + 80], fill=g, outline=gd, width=4)
        poly([(cx - 53, cy - 25), (cx, cy - 110), (cx + 53, cy - 25)])
        d.ellipse([cx - 78, cy - 78, cx + 78, cy + 78], outline=g, width=3)
        d.ellipse([cx - 92, cy - 92, cx + 92, cy + 92], outline=(255, 255, 255, 60), width=2)
    elif kind == "wrench":  # 建筑大师：扳手
        d.arc([cx - 70, cy - 70, cx + 70, cy + 70], 30, 330, fill=g, width=14)
        d.line([(cx + 55, cy + 45), (cx + 95, cy + 95)], fill=g, width=16)
        d.line([(cx + 95, cy + 95), (cx + 115, cy + 75)], fill=g, width=16)
    elif kind == "sparkle":  # 超级兵种：四角星
        pts = []
        import math
        for i in range(8):
            r = 110 if i % 2 == 0 else 34
            ang = math.pi / 2 + i * math.pi / 4
            pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
        poly(pts)
        d.ellipse([cx - 16, cy - 16, cx + 16, cy + 16], fill=g, outline=gd)


def make_card(card_id, name, c1, c2, kind, short_label):
    img = vertical_gradient(c1, c2).convert("RGBA")
    glow = radial_overlay((SIZE, SIZE), (256, 120), 360, (255, 220, 150), 90)
    vignette = radial_overlay((SIZE, SIZE), (256, 256), 420, (0, 0, 0), 150, dark=True)
    img = Image.alpha_composite(img, glow)
    img = Image.alpha_composite(img, vignette)

    d = ImageDraw.Draw(img)
    d.rounded_rectangle([10, 10, SIZE - 10, SIZE - 10], radius=26, outline=GOLD_DARK, width=6)
    d.rounded_rectangle([22, 22, SIZE - 22, SIZE - 22], radius=18, outline=(255, 255, 255, 60), width=2)

    # 图标（带阴影）
    emblem = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ed = ImageDraw.Draw(emblem)
    draw_emblem(ed, 256, 200, kind)
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    draw_emblem(sd, 256, 208, kind)
    shadow = shadow.filter(ImageFilter.GaussianBlur(8))
    shadow.putalpha(shadow.getchannel("A").point(lambda a: int(a * 0.55)))
    img = Image.alpha_composite(img, shadow)
    img = Image.alpha_composite(img, emblem)
    d = ImageDraw.Draw(img)

    # 底部名称带
    band = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    bd = ImageDraw.Draw(band)
    bd.rounded_rectangle([40, 416, SIZE - 40, 486], radius=20, fill=(0, 0, 0, 110), outline=GOLD_DARK, width=3)
    img = Image.alpha_composite(img, band)
    d = ImageDraw.Draw(img)

    # 右上角种类徽标
    font_cat = ImageFont.truetype(FONT_REG, 20)
    cat_bbox = d.textbbox((0, 0), short_label, font=font_cat)
    cat_w = cat_bbox[2] - cat_bbox[0] + 18
    chip = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    cd = ImageDraw.Draw(chip)
    cd.rounded_rectangle([SIZE - 34 - cat_w, 34, SIZE - 34, 34 + 30], radius=15, fill=(0, 0, 0, 90), outline=GOLD_DARK, width=2)
    img = Image.alpha_composite(img, chip)
    d = ImageDraw.Draw(img)
    d.text((SIZE - 34 - cat_w / 2, 49), short_label, font=font_cat, fill=GOLD, anchor="mm")

    font_name = ImageFont.truetype(FONT_BOLD, 38)
    font_id = ImageFont.truetype(FONT_REG, 22)
    d.text((256, 451), name, font=font_name, fill=WHITE, anchor="mm")
    d.text((44, 44), card_id.upper(), font=font_id, fill=(255, 255, 255, 160), anchor="mm")

    return img.convert("RGB")


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    total = 0
    for cat_key, (prefix, c1, c2, kind, short_label) in CATEGORIES.items():
        names = CARD_NAMES[cat_key]
        for i, name in enumerate(names):
            card_id = f"{prefix}{i + 1:02d}"
            img = make_card(card_id, name, c1, c2, kind, short_label)
            img.save(os.path.join(OUT_DIR, f"{card_id}.png"), "PNG")
            total += 1
    print(f"done: {total} images")


if __name__ == "__main__":
    main()