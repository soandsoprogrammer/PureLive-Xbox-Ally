"""A07.25 the mini window as one design: 5.4.1 as it is, and the new design.

5.4.1 (tag v5.4.1, A07.8 + A07.22 + A07.24):
  window, buttons    apps/pure_live/lib/features/live_play/mini/mini_player.dart:424-640
      (back top-left, mute + close top-right, name top centre from 240 wide,
      danmaku + picture-in-picture along the bottom from 240 x 170, the grip
      in the bottom corner towards the screen's middle, play/pause centre;
      compact below 260 x 150: no mute, centre 48)
  sizes, places      apps/pure_live/lib/features/live_play/logic/mini_window.dart:102-375
      (220 wide on a phone, 16 from the sides, above the home's bottom bar,
      released windows slide to the nearer side, past an edge tucked with
      40 showing)
  the home behind    A07.8's simplified home page

    python3 docs/A-界面设计/A07-直播间界面/A07.25-小窗整体设计/src/gen.py
    python3 tools/ui/mock/render.py docs/A-界面设计/A07-直播间界面/A07.25-小窗整体设计/src --annotate
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import smock  # noqa: E402  (settings rows, the same as A11.3)

CSS = '''
.bg{position:absolute;inset:0}
.home{position:absolute;inset:0;background:var(--surface);display:flex;flex-direction:column}
.hb{height:56px;display:flex;align-items:center;flex:none;color:var(--onv)}
.htabs{flex:1;min-width:0;display:flex;gap:22px;padding:0 6px;font-size:15px;color:var(--onv);white-space:nowrap;overflow:hidden;align-self:stretch;align-items:stretch}
.htabs span{position:relative;display:flex;align-items:center}
.htabs .on{color:var(--primary);font-weight:600}
.htabs .on::after{content:'';position:absolute;left:0;right:0;bottom:0;height:3px;border-radius:3px 3px 0 0;background:var(--primary)}
.grid{display:grid;gap:10px;padding:6px 10px;align-content:start;grid-auto-rows:max-content;flex:1;min-height:0;overflow:hidden}
.card{border-radius:16px;background:var(--scl);overflow:hidden}
.card .img{aspect-ratio:16/9;background:center/cover}
.card .t{font-size:13px;line-height:18px;padding:6px 10px 0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.card .s{font-size:12px;line-height:16px;color:var(--onv);padding:2px 10px 9px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.nav{height:80px;flex:none;background:var(--scc);display:flex}
.nav>div{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:4px;font-size:12px;font-weight:500;color:var(--onv)}
.nav i{width:64px;height:32px;border-radius:16px;display:grid;place-items:center;font-style:normal}
.nav .on{color:var(--on)}.nav .on i{background:var(--sc);color:var(--osc)}
.inset{height:16px;flex:none;background:var(--scc)}
.cap{position:absolute;z-index:44;font:500 11px 'Noto Sans SC';padding:3px 7px;border-radius:5px;background:rgba(0,0,0,.55);color:#fff;white-space:nowrap}
.cap.big{font-size:13px;padding:5px 9px;line-height:1.45;white-space:normal}
/* ---------- the mini window (5.4.1: square corners, floating shadow) ---------- */
.mw{position:absolute;z-index:30;overflow:hidden;background:#000 url(.cache/img/158.jpg) center 55%/cover;box-shadow:0 8px 24px rgba(0,0,0,.38),0 0 0 1px rgba(255,255,255,.10)}
.mw .d{position:absolute;z-index:2;white-space:nowrap;color:#fff;font-weight:500;line-height:1;text-shadow:0 0 1px #000,0 0 1px #000,0 0 2px #000;opacity:.9}
.mw .c{position:absolute;display:grid;place-items:center;border-radius:50%;background:rgba(0,0,0,.45);color:#fff;z-index:3}
.mw .nm{position:absolute;z-index:3;color:#fff;font-size:14px;font-weight:600;text-shadow:0 0 2px #000,0 0 4px rgba(0,0,0,.6);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;text-align:center}
.mb{position:absolute;left:6px;bottom:6px;z-index:2;height:20px;padding:0 7px 0 6px;border-radius:10px;background:var(--rec);color:#fff;font:600 12px/20px 'Noto Sans SC';font-feature-settings:'tnum';display:flex;align-items:center;gap:4px}
.mb i{width:6px;height:6px;border-radius:3px;background:#fff}
/* the new corner grip: a quarter disc in the corner with an L inside, not a round button */
.gq{position:absolute;z-index:3;width:44px;height:44px;background:rgba(0,0,0,.55);box-shadow:inset 0 0 0 1px rgba(255,255,255,.22)}
.gq.bl{left:0;bottom:0;border-top-right-radius:44px}
.gq.br{right:0;bottom:0;border-top-left-radius:44px}
.gq::after{content:'';position:absolute;width:16px;height:16px;border:3px solid #fff}
.gq.bl::after{left:8px;bottom:8px;border-top:0;border-right:0;border-bottom-left-radius:3px}
.gq.br::after{right:8px;bottom:8px;border-top:0;border-left:0;border-bottom-right-radius:3px}
/* tucked: the strip that shows, its handle */
.hd{position:absolute;z-index:4;width:6px;height:36px;border-radius:3px;background:rgba(255,255,255,.9);box-shadow:0 0 0 1px rgba(0,0,0,.25)}
/* drawing aids */
.ghost{position:absolute;z-index:29;border:2px dashed var(--primary);background:color-mix(in srgb,var(--primary) 8%,transparent)}
.zone{position:absolute;z-index:31;background:rgba(220,40,40,.28)}
.okz{position:absolute;z-index:32;border:2px dashed #1E9E58;background:rgba(30,158,88,.16)}
.reach{position:absolute;z-index:28;border:2px dashed var(--primary);border-radius:2px}
.lbl{position:absolute;z-index:45;font:600 12px/1.4 'Noto Sans SC';color:var(--primary);background:rgba(255,255,255,.92);padding:2px 6px;border-radius:4px;white-space:nowrap}
.lbl.red{color:#C62828}.lbl.grn{color:#14783F}
.tap{position:absolute;z-index:46;width:34px;height:34px;border-radius:17px;background:rgba(255,255,255,.55);border:2px solid rgba(255,255,255,.95);box-shadow:0 0 0 6px rgba(255,255,255,.22)}
.svg{position:absolute;inset:0;z-index:47;pointer-events:none;overflow:visible}
.ring{position:absolute;z-index:46;border:3px solid #FFB300;border-radius:50%}
/* system surroundings */
.ln{position:absolute;inset:0;background:url(.cache/img/338.jpg) center/cover}
.ln::before{content:'';position:absolute;inset:0;background:rgba(0,0,0,.18)}
.ln .status{position:relative;z-index:2;color:#fff}
.apps{position:absolute;left:30px;right:30px;top:118px;display:grid;grid-template-columns:repeat(4,1fr);gap:34px 0;justify-items:center}
.apps i,.dock i{width:56px;height:56px;border-radius:18px;display:block}
.dock{position:absolute;left:30px;right:30px;bottom:44px;display:flex;justify-content:space-between}
.sbar{position:absolute;left:24px;right:24px;bottom:124px;height:48px;border-radius:24px;background:rgba(255,255,255,.82)}
/* another app (a chat, drawn plainly) */
.oa{position:absolute;inset:0;background:#EDEDED;display:flex;flex-direction:column}
.oa .top{height:56px;flex:none;display:flex;align-items:center;justify-content:center;font-size:16px;font-weight:600;color:#222;background:#EDEDED;position:relative}
.oa .top .mr{position:absolute;left:14px}
.oa .msgs{flex:1;padding:8px 12px;display:flex;flex-direction:column;gap:14px}
.oa .m{display:flex;gap:8px;align-items:flex-start}.oa .m.me{flex-direction:row-reverse}
.oa .m i{width:38px;height:38px;border-radius:6px;flex:none;display:block}
.oa .m span{max-width:230px;padding:9px 12px;border-radius:6px;background:#fff;font-size:15px;line-height:1.45;color:#222}
.oa .m.me span{background:#95EC69}
.oa .in{height:56px;flex:none;background:#F7F7F7;display:flex;align-items:center;gap:10px;padding:0 12px}
.oa .in b{flex:1;height:38px;border-radius:6px;background:#fff;display:block}
/* the room page (U.2a) behind the button press */
.snk{position:absolute;left:12px;right:12px;z-index:35;min-height:48px;border-radius:4px;background:#2E3135;color:#EFF0F7;font-size:14px;display:flex;align-items:center;padding:0 8px 0 16px;box-shadow:0 3px 8px rgba(0,0,0,.25)}
.snk .x{flex:1}.snk b{color:#A8C8FF;font-weight:600;padding:0 8px;line-height:36px}
/* close-up sheets */
.sheet0{position:absolute;inset:0;background:var(--scc)}
.cell{position:absolute;background:#D9DDE3;overflow:hidden;border-radius:6px}
.cell .scr{position:absolute;inset:0;background:url(.cache/img/219.jpg) center/cover;filter:saturate(.5) brightness(1.05);opacity:.55}
.ctitle{position:absolute;font:600 14px/1.4 'Noto Sans SC';color:var(--on)}
.ctext{position:absolute;font:13px/1.55 'Noto Sans SC';color:var(--onv)}
.edge{position:absolute;top:0;bottom:0;width:3px;background:#5B6470;z-index:20}
'''

mr = lambda n, s=24: f'<span class="mr" style="font-size:{s}px">{n}</span>'
mi = lambda n, s=24: f'<span class="mi" style="font-size:{s}px">{n}</span>'
rx = lambda c, s=24: f'<span class="rx" style="font-size:{s}px">&#x{c};</span>'
ci = lambda c, s=24: f'<span class="ci" style="font-size:{s}px">&#x{c};</span>'

DMS = ['前排支持！', '这首好好听', '晚风今天状态好好', '来了来了', '晚上好～', '主播声音太温柔了']
CARDS = [('111', '周末老爷车巡游现场', '车库阿杰'), ('169', '小狗满草地跑一下午', '柴柴日记'), ('219', '草原上的猎豹妈妈', '野生镜头'),
         ('225', '下午茶时间 聊聊天', '茶馆小周'), ('274', '纽约时代广场，夜游直播', '城市漫游'), ('304', '调音台教学 第 12 课', '录音棚老王'),
         ('342', '台北夜市一路吃过去', '阿明在台北'), ('360', '花店开门 今天进了新货', '花间小铺'), ('250', '老相机修复全过程', '胶片修理铺'),
         ('292', '一人食 晚饭做什么', '厨房小林')]
TABS = ['哔哩哔哩', '斗鱼', '虎牙', '抖音', '快手', '网易CC']
STATUS = ('<div class="status"><span>21:36</span><span class="r"><span class="mi">signal_cellular_alt</span>'
          '<span class="mi">wifi</span><span class="mi">battery_full</span></span></div>')

# phone: 393 x 852; status bar 36; bottom inset 16; home bottom bar 80
W, H = 393, 852
TOP, INSET, NAV, M = 36, 16, 80, 16
PW, PH = 220, 124                       # the default window on a phone (A07.8 c6)
DX, DY = W - M - PW, H - INSET - NAV - M - PH  # its default place: 157, 616


def page(w, h, scale, body, root='ph', crop=False, extra=''):
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h}@{scale}{" crop" if crop else ""}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}{extra}</style></head>'
            f'<body><div class="{root}" style="--w:{w}px;--h:{h}px">{body}</div></body></html>')


def cards(n, cols=2):
    return (f'<div class="grid" style="grid-template-columns:repeat({cols},1fr)">'
            + ''.join(f'<div class="card"><div class="img" style="background-image:url(.cache/img/{i}.jpg)"></div><div class="t">{t}</div><div class="s">{s}</div></div>'
                      for i, t, s in CARDS[:n]) + '</div>')


def home_phone():
    items = [('ee0b', '关注', False), ('ed32', '热门', True), ('ea42', '分区', False), ('ec54', '录制中心', False)]
    nav = ''.join(f'<div class="{"on" if on else ""}"><i>{rx(code)}</i>{label}</div>' for code, label, on in items)
    return ('<div class="home">' + STATUS + '<div class="hb"><div class="ib">' + mr('menu') + '</div><div class="htabs">'
            + ''.join(f'<span class="{"on" if i == 0 else ""}">{t}</span>' for i, t in enumerate(TABS))
            + '</div><div class="ib">' + rx('f3d0') + '</div></div>' + cards(10) + f'<div class="nav">{nav}</div><div class="inset"></div></div>'
            '<div class="gesture"></div>')


def launcher():
    cols = ['#F4C7B8', '#BFD8F2', '#C8E6C9', '#FFE0A3', '#D7C8F0', '#F2C1D6', '#B9E2E0', '#E8E0D0']
    return ('<div class="ln"><div class="status"><span>21:40</span><span class="r"><span class="mi">signal_cellular_alt</span><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>'
            '<div class="apps">' + ''.join(f'<i style="background:{c}"></i>' for c in cols) + '</div><div class="sbar"></div>'
            '<div class="dock">' + ''.join(f'<i style="background:{c}"></i>' for c in cols[:4]) + '</div></div>'
            '<div class="gesture" style="background:rgba(255,255,255,.7)"></div>')


def other_app():
    msgs = [(False, '晚上一起打游戏吗？'), (True, '等我看完这场直播'), (False, '哪个主播？'), (True, '晚风的电台，点歌接龙到天亮'), (False, '发个链接我也去听听')]
    av = ['#9FB7D8', '#E5B98F']
    return ('<div class="oa">' + STATUS + '<div class="top">' + mr('arrow_back_ios_new', 20) + '小林</div><div class="msgs">'
            + ''.join(f'<div class="m{" me" if me else ""}"><i style="background:{av[me]}"></i><span>{t}</span></div>' for me, t in msgs)
            + '</div><div class="in">' + mr('keyboard_voice', 26) + '<b></b>' + mr('add_circle_outline', 28) + '</div><div style="height:16px;background:#F7F7F7;flex:none"></div></div>'
            '<div class="gesture"></div>')


def room_page():
    return ('<div class="status"><span>21:36</span><span class="r"><span class="mi">signal_cellular_alt</span><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>'
            '<div class="appbar"><div class="back">' + mi('arrow_back') + '</div><span class="av" style="background-image:url(.cache/img/65.jpg)"></span>'
            '<div class="tt"><div class="n">晚风</div><div class="s">哔哩哔哩 · 唱见电台</div></div>'
            '<div class="fol on">' + rx('eb7b') + '已关注</div><div class="recbtn"><span class="ring"><i></i></span></div><div class="ib">' + rx('ea42') + '</div></div>'
            '<div class="video" style="background-image:url(.cache/img/158.jpg)"><div class="vtop"><div class="title">深夜电台 · 点歌接龙到天亮</div>'
            '<div class="ib vic">' + rx('ee05', 21) + '</div><div class="ib vic">' + rx('f235') + '</div><div class="ib vic" data-n="1" data-tag="chg" data-at="bl">' + ci('e806') + '</div></div>'
            '<div class="vbot"><div class="ib vic">' + mr('pause', 28) + '</div><div class="ib vic">' + mr('refresh') + '</div><div class="ib vic"><span class="dmk open"></span></div>'
            '<div class="ib vic"><span class="dmk set"></span></div><div style="flex:1"></div><div class="ib vic">' + mr('screen_rotation_alt', 21) + '</div><div class="ib vic">' + mr('fullscreen', 26) + '</div></div></div>'
            '<div class="info"><div class="l1"><span class="t">深夜电台 · 点歌接龙到天亮</span><span class="more">详情' + rx('ea4e', 18) + '</span></div>'
            '<div class="l2"><div class="figs"><span class="fg"><span class="mr">people_alt</span><b>1.2万</b></span><span class="fg"><span class="mr">whatshot</span><b>84.7万</b></span>'
            '<span class="fg"><span class="mr">schedule</span><b>2:18</b></span></div><div class="chip">原画' + rx('ea4e', 18) + '</div><div class="chip">线路1' + rx('ea4e', 18) + '</div></div></div><hr>'
            '<div class="tabs"><div class="on">弹幕列表</div><div>醒目留言<span class="badge">2</span></div><div>弹幕设置</div><div>屏蔽管理</div></div>'
            + ''.join(f'<div class="row"><span class="u">{u}：</span>{t}</div>' for u, t in [('路过的风', '主播声音太温柔了'), ('夜猫子', '可以点《晴天》吗'), ('一只小熊', '这首歌好好听'),
                                                                                         ('清欢', '下一首想听《晚风》'), ('风吹麦浪', '来了来了'), ('小林同学', '今天也是被治愈的一天')])
            + '<div class="gesture"></div>')


# ---------- the window ----------
def danmaku(w, h, font=10, n=5):
    track = max(font * 1.8, font + 10)
    rows = max(1, int(h * 0.5 // track))
    starts = [0.42, 0.05, 0.26, 0.60]
    out, k = '', 0
    for r in range(rows):
        x = starts[r % len(starts)] * w
        while k < n and x < w * 0.95:
            text = DMS[k]
            out += f'<div class="d" style="font-size:{font:.1f}px;left:{x:.0f}px;top:{r * track + (track - font) / 2 + 2:.0f}px">{text}</div>'
            x += len(text) * font + font * 3
            k += 1
            if r == 0 and k >= 2:
                break
            if r > 0:
                break
    return out


def attrs(n=None, tag=None, at=None):
    return (f' data-n="{n}"' if n else '') + (f' data-tag="{tag}"' if n and tag else '') + (f' data-at="{at}"' if n and at else '')


def circ(x, y, d, inner, n=None, tag=None, at=None):
    return f'<div class="c" style="left:{x}px;top:{y}px;width:{d}px;height:{d}px"{attrs(n, tag, at)}>{inner}</div>'


def buttons(w, h, *, grip='bl', grip_style='disc', n=False, paused=False):
    """The 5.4.1 button layer (mini_player.dart:424-640) for a w x h window.

    grip: 'bl' / 'br' (one grip), 'both', or None; grip_style: 'disc' (5.4.1:
    a round 48 button with an arrow out of the corner) or 'corner' (new: a
    quarter disc with an L)."""
    N = (lambda k: k) if n else (lambda k: None)
    compact = w < 260 or h < 150
    out = circ(4, 4, 48, rx('eff2', 20), n=N(1), tag='keep', at='tl')
    out += circ(w - 52, 4, 48, mr('close', 20), n=N(2), tag='keep', at='tr')
    if not compact:
        out += circ(w - 104, 4, 48, mr('volume_up', 20), n=N(6), tag='keep', at='tc')
    if w >= 240:
        right = 48 * 2 + 16 if not compact else 48 + 12
        out += f'<div class="nm" style="left:{48 + 12}px;right:{right}px;top:18px"{attrs(N(7), "keep", "tc")}>晚风</div>'
    cs = 48 if compact else 58
    out += circ(round(w / 2 - cs / 2), round(h / 2 - cs / 2), cs, mr('play_arrow' if paused else 'pause', 28 if cs == 58 else 24), n=N(3), tag='keep', at='c')
    corners = {'bl': ['bl'], 'br': ['br'], 'both': ['bl', 'br'], None: []}[grip]
    for i, side in enumerate(corners):
        nn = N(4) if i == 0 else N(None)
        if grip_style == 'disc':
            x = 4 if side == 'bl' else w - 52
            out += circ(x, h - 52, 48, mr('south_west' if side == 'bl' else 'south_east', 20), n=nn, tag='keep', at='bl' if side == 'bl' else 'br')
        else:
            out += f'<div class="gq {side}"{attrs(nn, "chg", "bl" if side == "bl" else "br")}></div>'
    if h >= 170 and w >= 240:
        row_right = grip == 'bl' or grip is None
        if grip == 'both':
            x0 = round(w / 2 - 50)
        else:
            x0 = w - 4 - 100 if row_right else 4
        out += circ(x0, h - 52, 48, '<span class="dmk open" style="transform:scale(.85)"></span>', n=N(8), tag='keep', at='bl')
        out += circ(x0 + 52, h - 52, 48, ci('e806', 20), n=N(9), tag='keep', at='br')
    return out


def window(x, y, w, h, *, inner='', dm=True, rec=False, n=None, at='tc', style='', img=None):
    st = f'left:{x}px;top:{y}px;width:{w}px;height:{h}px' + (f';background-image:url(.cache/img/{img}.jpg)' if img else '') + (';' + style if style else '')
    a = f' data-n="{n}" data-tag="keep" data-at="{at}"' if n else ''
    return f'<div class="mw" style="{st}"{a}>' + (danmaku(w, h) if dm else '') + ('<div class="mb"><i></i>12:34</div>' if rec else '') + inner + '</div>'


def svg(*paths, w=W, h=H):
    defs = ('<defs><marker id="ah" viewBox="0 0 10 10" refX="7" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse">'
            '<path d="M0,0 L10,5 L0,10 z" fill="#FFB300"/></marker>'
            '<marker id="ab" viewBox="0 0 10 10" refX="7" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse">'
            '<path d="M0,0 L10,5 L0,10 z" fill="#3D6FB6"/></marker></defs>')
    return f'<svg class="svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{defs}{"".join(paths)}</svg>'


def arrow(x1, y1, x2, y2, color='#FFB300', both=False, width=4, dash=''):
    mk = 'ah' if color == '#FFB300' else 'ab'
    d = f' stroke-dasharray="{dash}"' if dash else ''
    start = f' marker-start="url(#{mk})"' if both else ''
    return (f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="rgba(0,0,0,.35)" stroke-width="{width + 3}" stroke-linecap="round"{d}/>'
            f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="{width}" stroke-linecap="round" marker-end="url(#{mk})"{start}{d}/>')


def syn(top=10):
    return f'<div class="syn" style="top:{top}px">示意图片</div>'


# ---------- 5.4.1 ----------
def now_phone():
    win = window(DX, DY, PW, PH, n=5, inner=buttons(PW, PH, grip='bl', n=True))
    return page(W, H, 3, home_phone() + win + '<div class="cap" style="left:16px;top:104px">5.4.1：小窗在右边时，把手在左下角</div>' + syn())


def now_large():
    w, h = 340, 191
    x, y = W - M - w, H - INSET - NAV - M - h
    win = window(x, y, w, h, n=5, inner=buttons(w, h, grip='bl', n=True))
    return page(W, H, 3, home_phone() + win + '<div class="cap" style="left:16px;top:104px">5.4.1：放大以后多出静音、主播名、弹幕开关和画中画</div>' + syn())


def now_swap():
    """5.4.1: dragged to the left half, the grip and the bottom row change sides."""
    w, h = 300, 169
    y = 300
    win = window(M, y, w, h, inner=buttons(w, h, grip='br'))
    note = ('<div class="cap big" style="left:16px;top:104px;right:16px">5.4.1：拖到屏幕左半边以后，把手换到右下角，'
            '弹幕开关和画中画换到左下角（用户说的“左下角和右下角换位置了”）</div>')
    return page(W, H, 3, home_phone() + win + note + syn())


# ---------- the new design ----------
def new_phone():
    win = window(DX, DY, PW, PH, n=5, inner=buttons(PW, PH, grip='br', grip_style='corner', n=True))
    return page(W, H, 3, home_phone() + win + '<div class="cap" style="left:16px;top:104px">新设计：把手固定在右下角，换成角上的样子</div>' + syn())


def new_large():
    w, h = 340, 191
    x, y = W - M - w, H - INSET - NAV - M - h
    win = window(x, y, w, h, n=5, inner=buttons(w, h, grip='br', grip_style='corner', n=True))
    return page(W, H, 3, home_phone() + win + '<div class="cap" style="left:16px;top:104px">新设计：弹幕开关和画中画固定在左下角，不换边</div>' + syn())


def grip_sheet():
    """Close-ups: pulling the grip with the window on the right, on the left,
    a pinch, a tap on the grip."""
    cw, ch, gap, pad = 380, 300, 24, 24
    SW, SH = pad * 2 + cw * 2 + gap, pad * 2 + (ch + 92) * 2
    out = '<div class="sheet0"></div>'

    def cell(cx, cy, title, text, body):
        return (f'<div class="cell" style="left:{cx}px;top:{cy}px;width:{cw}px;height:{ch}px"><div class="scr"></div>{body}</div>'
                f'<div class="ctitle" style="left:{cx}px;top:{cy + ch + 8}px">{title}</div>'
                f'<div class="ctext" style="left:{cx}px;top:{cy + ch + 30}px;width:{cw}px">{text}</div>')

    # 1. on the right: the grip at the bottom right; left or down = bigger, the top-right corner stays
    w0, h0, w1, h1 = 176, 99, 300, 169
    x0, y0 = cw - 12 - w0, 30
    b1 = ('<div class="edge" style="right:0"></div>'
          + f'<div class="ghost" style="left:{cw - 12 - w1}px;top:{y0}px;width:{w1}px;height:{h1}px"></div>'
          + window(x0, y0, w0, h0, inner=buttons(w0, h0, grip='br', grip_style='corner'), dm=False)
          + svg(arrow(x0 + w0 - 20, y0 + h0 - 16, cw - 12 - w1 + 60, y0 + h1 - 30), arrow(x0 + w0 - 20, y0 + h0 - 16, x0 + w0 - 20, y0 + h1 + 2), w=cw, h=ch)
          + f'<div class="lbl" style="left:{cw - 12 - w1 + 4}px;top:{y0 + h1 + 8}px">往左或往下拉：变大（右上角不动）</div>'
          + f'<div class="lbl" style="left:{cw - 12 - w1 + 4}px;top:{y0 + h1 + 32}px">往右推：变小</div>')
    out += cell(pad, pad, '① 小窗在右边：右下角的把手往左或往下拉', '把手一直在右下角，不换边（你选的）。靠右边时往右没地方，往左拉就是变大，窗口往屏幕中间长；往下拉也变大。画面比例不变，从 160 宽一直到和屏幕一样宽。', b1)
    # 2. on the left: right or down = bigger, the top-left corner stays
    x0 = 12
    b2 = ('<div class="edge" style="left:0"></div>'
          + f'<div class="ghost" style="left:12px;top:{y0}px;width:{w1}px;height:{h1}px"></div>'
          + window(x0, y0, w0, h0, inner=buttons(w0, h0, grip='br', grip_style='corner'), dm=False)
          + svg(arrow(x0 + w0 - 20, y0 + h0 - 16, x0 + w1 - 30, y0 + h1 - 20), w=cw, h=ch)
          + f'<div class="lbl" style="left:{x0 + 34}px;top:{y0 + h1 + 8}px">靠左边时往右、往下拉变大（左上角不动）</div>')
    out += cell(pad + cw + gap, pad, '② 小窗在左边：往右或往下拉', '同一个把手，往屏幕中间那边拉就是变大，往回推变小。把手所在的角离屏幕边太近时，这一块不触发系统返回手势（K90 上发现的）。', b2)
    # 3. pinch anywhere
    w2, h2 = 220, 124
    x2, y2 = (cw - w2) // 2, 70
    b3 = (window(x2, y2, w2, h2, dm=False)
          + f'<div class="tap" style="left:{x2 + 52}px;top:{y2 + 58}px"></div><div class="tap" style="left:{x2 + w2 - 86}px;top:{y2 + 30}px"></div>'
          + svg(arrow(x2 + 66, y2 + 76, x2 + 10, y2 + 110), arrow(x2 + w2 - 70, y2 + 46, x2 + w2 + 8, y2 + 6), w=cw, h=ch)
          + f'<div class="lbl" style="left:{x2}px;top:{y2 + h2 + 34}px">两指张开变大、捏合变小；中心不动</div>')
    out += cell(pad, pad + ch + 92, '③ 两指缩放（照 5.4.1）', '按钮没显示时，两指放在画面任何地方都行，和系统画中画一样。', b3)
    # 4. a tap on the grip says what it is
    x3, y3 = 90, 70
    b4 = (window(x3, y3, w2, h2, inner=buttons(w2, h2, grip='br', grip_style='corner'), dm=False)
          + f'<div class="tap" style="left:{x3 + w2 - 40}px;top:{y3 + h2 - 40}px"></div>'
          + f'<div class="tip" style="left:{x3 + w2 - 120}px;top:{y3 + h2 + 12}px;font-size:13px">拖动调整小窗大小</div>')
    out += cell(pad + cw + gap, pad + ch + 92, '④ 点一下把手', '把手不是按钮：点一下只弹出“拖动调整小窗大小”。它的样子换成角上的四分之一圆和直角线，和圆形按钮区分开。', b4)
    return page(SW, SH, 2, out, root='win')


def new_reach():
    top = TOP + 4
    bottom = H - INSET - 4
    zone = f'<div class="reach" style="left:2px;right:2px;top:{top}px;height:{bottom - top}px"></div>'
    w, h = 220, 124
    up = window(W - M - w, top, w, h, dm=True)
    down = window(M, bottom - h, w, h, dm=True)
    ghost = f'<div class="ghost" style="left:{DX}px;top:{DY}px;width:{PW}px;height:{PH}px;border-style:dotted"></div>'
    labels = (f'<div class="lbl" style="left:12px;top:{top + 8}px">上：贴到状态栏下沿</div>'
              f'<div class="lbl" style="left:12px;top:{bottom - h - 30}px">下：贴到手势条上沿，可以盖住底部导航</div>'
              f'<div class="lbl" style="left:{DX - 8}px;top:{DY - 26}px">虚线：刚出现时的位置（照 5.4.1）</div>')
    return page(W, H, 3, home_phone() + zone + ghost + up + down + labels + syn(), root='ph')


def new_tuck1():
    """Tucked into the right side: a fifth (at least 56) shows, a handle on it;
    the back-gesture zone and the part kept from it."""
    w, h = 220, 124
    peek = 56
    y = 420
    win = window(W - peek, y, w, h, dm=False, style='', inner=f'<div class="hd" style="left:14px;top:{(h - 36) // 2}px"></div>')
    zone = f'<div class="zone" style="right:0;top:{TOP}px;width:24px;bottom:{INSET}px"></div>'
    ok = f'<div class="okz" style="right:0;top:{y - 38}px;width:{peek}px;height:{h + 76}px"></div>'
    labels = (f'<div class="lbl red" style="right:30px;top:{TOP + 120}px">红色：系统返回手势区（约 24 宽，各家不同）</div>'
              f'<div class="lbl grn" style="right:{peek + 8}px;top:{y - 30}px">绿色：这一条不触发返回（最多 200 高）</div>'
              f'<div class="lbl" style="right:{peek + 8}px;top:{y + h // 2 - 12}px">露出 1/5，至少 56；照常播放</div>'
              f'<div class="lbl" style="right:{peek + 8}px;top:{y + h + 14}px">白色竖条：抓这里</div>')
    return page(W, H, 3, home_phone() + win + zone + ok + labels + syn(), root='ph')


def new_tuck2():
    w, h = 220, 124
    peek = 56
    y = 420
    win = window(W - peek, y, w, h, dm=False, inner=f'<div class="hd" style="left:14px;top:{(h - 36) // 2}px"></div>')
    ghost = f'<div class="ghost" style="left:{W - M - w}px;top:{y}px;width:{w}px;height:{h}px"></div>'
    tap = f'<div class="tap" style="left:{W - peek}px;top:{y + (h - 34) // 2}px"></div>'
    arr = svg(arrow(W - peek + 14, y + h - 22, W - M - w + 40, y + h - 22))
    labels = (f'<div class="lbl" style="left:{W - M - w}px;top:{y - 56}px">点一下露出的那条：滑回来</div>'
              f'<div class="lbl" style="left:{W - M - w}px;top:{y - 30}px">或者按住往里拖：跟着手指出来</div>'
              f'<div class="lbl" style="left:{W - M - w}px;top:{y + h + 12}px">起点在返回手势区外面，不会退出应用</div>')
    return page(W, H, 3, home_phone() + ghost + win + tap + arr + labels + syn(), root='ph')


def new_entry1():
    ring = '<div class="ring" style="left:335px;top:95px;width:48px;height:48px"></div>'
    return page(W, H, 3, room_page() + ring + '<div class="cap big" style="left:16px;top:160px">点画面上栏的小窗按钮</div>' + syn(), root='ph')


def new_entry2():
    win = window(DX, DY, PW, PH, rec=True)
    note = ('<div class="cap big" style="left:16px;right:16px;top:104px">直播间缩成小窗，回到上一页（这里是首页）；人还在应用里，'
            '不会退到桌面。画面、弹幕、录制都接着，不重新加载。</div>')
    return page(W, H, 3, home_phone() + win + note + syn(), root='ph')


def new_outside1():
    win = window(DX, DY + 30, PW, PH, rec=True)
    note = ('<div class="cap big" style="left:16px;right:16px;top:60px">小窗开着时回到桌面：同一个小窗留在桌面上，'
            '还在原来的位置和大小；按钮、拖动、改大小、收边都和应用里一样</div>')
    return page(W, H, 3, launcher() + win + note + syn(top=40), root='ph')


def new_outside2():
    w, h = 220, 124
    win = window(W - M - w, TOP + 4, w, h, inner=buttons(w, h, grip='br', grip_style='corner'))
    note = ('<div class="cap big" style="left:16px;right:16px;top:470px">在别的应用里也能拖到最上面。点“回到直播间”打开纯粹直播的这个直播间；'
            '✕ 停止播放并关掉小窗</div>')
    return page(W, H, 3, other_app() + win + note + syn(), root='ph')


def new_tip():
    win = window(DX, DY, PW, PH)
    snk = ('<div class="snk" style="bottom:110px"><div class="x">小窗可以留在其他应用上面播放</div><b>去开启</b></div>')
    note = ('<div class="cap big" style="left:16px;right:16px;top:104px">没有给“显示在其他应用的上层”时离开应用：小窗先藏起来（声音按“后台播放”），'
            '回来还在原处。第一次回来时提示一次，以后不再提示。</div>')
    win2 = win.replace(f'top:{DY}px', f'top:{DY - 70}px')
    return page(W, H, 3, home_phone() + win2 + snk + note + syn(), root='ph')


def new_settings():
    S = smock
    rows = [
        S.sw('离开直播间时小窗播放', '返回离开直播间后，画面缩成应用内小窗继续播放', on=True, n=1, tag='keep'),
        S.link('小窗大小', '应用内小窗有多大；在小窗上两指缩放或拖动角上的把手也能调，会记住', val='中', n=2, tag='keep'),
        S.sw('离开应用时自动小窗', '在直播间回桌面或切到别的应用，缩成小窗留在其他应用上面；纯音频、暂停时除外', on=False, n=3, tag='chg'),
        S.link('在其他应用上层显示小窗', '离开应用时小窗留在其他应用上面；要在系统设置里打开“显示在其他应用的上层”', val='未开启', n=4, tag='add'),
        S.sw('改用系统画中画', '小窗按钮和离开应用都用系统画中画：不用悬浮窗权限，但按钮少、不能收边', on=False, n=5, tag='add'),
        S.link('小窗弹幕', '小窗和画中画里的弹幕样式', n=6, tag='keep'),
    ]
    body = S.bar('视频') + '<div style="padding:4px 0 24px">' + S.sec('小窗') + S.grp(rows) + '</div>'
    return S.page(W, 1100, 2, body, crop=True, long=True)


def j1_sheet():
    """The three ways of the grip, side by side."""
    cw, ch, gap, pad = 360, 250, 20, 24
    SW, SH = pad * 2 + cw * 3 + gap * 2, pad * 2 + ch + 110
    w, h = 320, 180
    out = '<div class="sheet0"></div>'
    opts = [
        ('定了：把手右下角，弹幕和画中画左下角', '你选的（2026-10-18）：以后不换边。靠右边时把手往左拉变大。', 'br', 'corner'),
        ('第 1 版建议的 A：把手左下角', '没采用。', 'bl', 'corner'),
        ('5.4.1：跟着屏幕左右半边换', '没采用：会换位置。', 'bl', 'disc'),
    ]
    for i, (title, text, grip, style) in enumerate(opts):
        cx = pad + i * (cw + gap)
        x, y = (cw - w) // 2, (ch - h) // 2
        body = window(x, y, w, h, dm=False, inner=buttons(w, h, grip=grip, grip_style=style))
        out += (f'<div class="cell" style="left:{cx}px;top:{pad}px;width:{cw}px;height:{ch}px"><div class="scr"></div>{body}</div>'
                f'<div class="ctitle" style="left:{cx}px;top:{pad + ch + 8}px">{title}</div>'
                f'<div class="ctext" style="left:{cx}px;top:{pad + ch + 30}px;width:{cw}px">{text}</div>')
    return page(SW, SH, 2, out, root='win')


def motion_sheet():
    """A07.25 M1-M5: the moves, drawn as a strip of moments."""
    cw, ch, gap, pad = 280, 300, 20, 24
    SW, SH = pad * 2 + cw * 4 + gap * 3, pad * 2 + ch + 120
    out = '<div class="sheet0"></div>'

    def cell(i, title, text, body):
        cx = pad + i * (cw + gap)
        return (f'<div class="cell" style="left:{cx}px;top:{pad}px;width:{cw}px;height:{ch}px"><div class="scr"></div>{body}</div>'
                f'<div class="ctitle" style="left:{cx}px;top:{pad + ch + 8}px">{title}</div>'
                f'<div class="ctext" style="left:{cx}px;top:{pad + ch + 30}px;width:{cw}px">{text}</div>')

    # M1: out of the picture into the corner
    big = (0, 20, cw, cw * 9 // 16)
    small = (cw - 12 - 120, ch - 12 - 68, 120, 68)
    mid = tuple(round(a + (b - a) * 0.55) for a, b in zip(big, small))
    b = (f'<div class="ghost" style="left:{big[0]}px;top:{big[1]}px;width:{big[2]}px;height:{big[3]}px;border-style:dotted"></div>'
         + f'<div class="ghost" style="left:{mid[0]}px;top:{mid[1]}px;width:{mid[2]}px;height:{mid[3]}px;border-style:dotted"></div>'
         + window(*small, dm=False)
         + svg(arrow(big[0] + big[2] / 2, big[1] + big[3] / 2, small[0] + 40, small[1] + 20), w=cw, h=ch))
    out += cell(0, 'M1 缩成小窗', '点小窗按钮或返回离开直播间：画面从直播间里的位置直接飞到小窗的位置、同时缩小，直播间页面在下面照常退出。弹簧（AppMotion.floatingSpring，约 0.3 秒），中途不重建播放器。', b)
    # M3: ✕
    w3 = (80, 110, 120, 68)
    b = (window(*w3, dm=False, style='opacity:.35;transform:scale(.85)')
         + f'<div class="ghost" style="left:{w3[0]}px;top:{w3[1]}px;width:{w3[2]}px;height:{w3[3]}px;border-style:dotted"></div>'
         + f'<div class="lbl" style="left:40px;top:{w3[1] + 90}px">缩到 0.85、变透明，0.18 秒</div>')
    out += cell(1, 'M2、M3 回直播间、关闭', '点 ✕：缩小并淡出（0.18 秒）再停播放；点回到直播间：稍放大并淡出（0.12 秒）再打开直播间。系统“移除动画”开着时直接到位。', b)
    # M4/M5: settle and tuck
    b = (window(cw - 40, 120, 120, 68, dm=False, inner='<div class="hd" style="left:10px;top:16px"></div>')
         + f'<div class="ghost" style="left:60px;top:120px;width:120px;height:68px;border-style:dotted"></div>'
         + svg(arrow(130, 150, cw - 30, 150), w=cw, h=ch)
         + '<div class="lbl" style="left:20px;top:210px">带着手指的速度滑过去，到边就停</div>')
    out += cell(2, 'M4、M5 松手、收边', '松手后带着手指速度滑到近的一边（照 5.4.1 / A03.4）；甩出边就收起，收好后竖条把手淡入（0.15 秒）；点一下或拖出来，同一根弹簧滑回来。', b)
    # M8: the bottom bar comes, the window moves up
    b = ('<div style="position:absolute;left:0;right:0;bottom:0;height:46px;background:var(--scc)"></div>'
         + f'<div class="ghost" style="left:{cw - 12 - 120}px;top:{ch - 12 - 68}px;width:120px;height:68px;border-style:dotted"></div>'
         + window(cw - 12 - 120, ch - 46 - 12 - 68, 120, 68, dm=False)
         + svg(arrow(cw - 72, ch - 40, cw - 72, ch - 70), w=cw, h=ch)
         + '<div class="lbl" style="left:12px;top:40px">换到有底部导航的页面、转屏、改“小窗大小”</div>')
    out += cell(3, 'M8 自己挪位置', '不是手指挪的位置变化（底部导航出现、转屏、窗口大小设置）：同一根弹簧平滑挪过去，不跳。手指拖动、改大小时不加这个动画（跟手）。', b)
    return page(SW, SH, 2, out, root='win')


OUT = {
    'now-phone': now_phone(), 'now-large': now_large(), 'now-swap': now_swap(),
    'new-phone': new_phone(), 'new-large': new_large(), 'new-grip': grip_sheet(), 'new-reach': new_reach(),
    'new-tuck-1': new_tuck1(), 'new-tuck-2': new_tuck2(), 'new-entry-1': new_entry1(), 'new-entry-2': new_entry2(),
    'new-outside-1': new_outside1(), 'new-outside-2': new_outside2(), 'new-tip': new_tip(), 'new-settings': new_settings(),
    'j1-grip': j1_sheet(), 'new-motion': motion_sheet(),
}
for name, html in OUT.items():
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
print(len(OUT), 'pages')
