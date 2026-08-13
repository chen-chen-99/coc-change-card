# 任务
为《部落冲突·卡牌冲突换卡助手》项目收集 **60 张兵种卡牌官方图片**，严格按项目命名规则命名，放入指定目录，并完成自查。

# 项目背景与关键路径
- 项目根目录：`D:\Projects\TraeProjects\buluochongtu`
- 图片存放目录：`D:\Projects\TraeProjects\buluochongtu\public\images\cards\`（该目录下已有 `README.md`，保留勿删）
- 数据库 `cards.image_url` 已统一指向 `images/cards/{卡牌ID}.png`，因此**只要文件名与卡牌ID一致，无需改任何代码或数据库**

# 命名规则（必须严格遵守）
- 文件名 = `卡牌ID` + `.png`，例如 `e01.png`、`d05.png`、`b11.png`、`s17.png`
- 全部小写、无空格、无中文、无特殊字符
- 必须恰好 60 张，文件名与下方清单的 card_id 一一对应，不能多也不能少

# 图片来源（重要）
卡牌图片使用《部落冲突》官方兵种立绘，来源为 **Clash of Clans Fandom Wiki**（clashofclans.fandom.com），每个兵种页面的顶部立绘/渲染图通常是透明背景 PNG。

依据 Supercell《玩家内容条款》，非商业性玩家内容可以使用游戏素材，但网站必须在页面展示免责声明（本项目已在页脚添加）：
> 此非官方作品，未获得Supercell认可。更多信息，请参阅 Supercell 玩家内容条款：www.supercell.com/en/fan-content-policy/cn/

因此请放心从 Fandom Wiki 获取官方兵种图片。**不要**使用其他非官方/AI 生成/第三方素材站的图，以保证玩家能一眼认出兵种。

# 图片要求
- 格式：**PNG**（不要使用 WebP/JPG，否则需同步改数据库）
- 来源：对应兵种的 Fandom Wiki 页面立绘（优先透明背景 PNG；若该兵种只有带背景的立绘，保留原背景即可，不要自行抠图）
- 尺寸：**512 × 512**（正方形）。源图非正方形时**等比缩放**（长边放到 512），再以透明背景**补齐**到 512×512，**不要裁剪兵种主体、不要拉伸变形**
- 大小：单张尽量控制在 50KB ~ 500KB，最大不超过 1MB（超出可无损/低损压缩）
- 内容：**不得修改兵种外观**（不改色、不加文字水印、不叠加装饰）；不要添加任何水印
- 网页实际显示很小（列表 84×84、推荐缩略图 36×36），但按 512×512 交付以保证清晰度

# 获取方式（workbuddy 执行步骤）
1. 打开 Clash of Clans Fandom Wiki：`https://clashofclans.fandom.com/wiki/{英文页面名}`（英文页面名见下方清单）
2. 下载页面顶部信息框（infobox）中的兵种立绘/渲染图（通常是透明 PNG）。若页面顶部图不理想，可在页面内找该兵种独立的立绘图
3. 按「图片要求」处理成 512×512 透明背景 PNG，命名为 `{卡牌ID}.png`
4. 覆盖写入 `public\images\cards\` 对应文件（文件名与卡牌ID一致，无需改任何代码）
5. 处理完后执行「完成标准」自查

# 60 张卡牌清单（卡牌ID = 文件名；英文名 = Fandom Wiki 页面名）
## 圣水卡牌（e01~e19）
| 文件名 | 卡牌名称 | Wiki 页面名（英文） |
| --- | --- | --- |
| e01.png | 野蛮人 | Barbarian |
| e02.png | 弓箭手 | Archer |
| e03.png | 巨人 | Giant |
| e04.png | 哥布林 | Goblin |
| e05.png | 炸弹人 | Wall Breaker |
| e06.png | 气球兵 | Balloon |
| e07.png | 法师 | Wizard |
| e08.png | 天使 | Healer |
| e09.png | 飞龙 | Dragon |
| e10.png | 皮卡超人 | P.E.K.K.A |
| e11.png | 飞龙宝宝 | Baby Dragon |
| e12.png | 掘地矿工 | Miner |
| e13.png | 雷电飞龙 | Electro Dragon |
| e14.png | 大雪怪 | Yeti |
| e15.png | 龙骑士 | Dragon Rider |
| e16.png | 雷霆泰坦 | Electro Titan |
| e17.png | 根蔓骑士 | Root Rider |
| e18.png | 巨矛投手 | Thrower |
| e19.png | 陨石戈仑 | Meteor Golem |

## 暗黑重油卡牌（d01~d13）
| 文件名 | 卡牌名称 | Wiki 页面名（英文） |
| --- | --- | --- |
| d01.png | 亡灵 | Minion |
| d02.png | 野猪骑士 | Hog Rider |
| d03.png | 瓦基里丽武神 | Valkyrie |
| d04.png | 戈仑石人 | Golem |
| d05.png | 女巫 | Witch |
| d06.png | 熔岩猎犬 | Lava Hound |
| d07.png | 巨石投手 | Bowler |
| d08.png | 戈仑冰人 | Ice Golem |
| d09.png | 英雄猎手 | Headhunter |
| d10.png | 守护者学徒 | Apprentice Warden |
| d11.png | 德鲁伊 | Druid |
| d12.png | 烈焰熔炉 | Furnace |
| d13.png | 废墟女巫 | Ruin Witch |

## 建筑大师基地卡牌（b01~b11）
| 文件名 | 卡牌名称 | Wiki 页面名（英文） |
| --- | --- | --- |
| b01.png | 狂暴野蛮人 | Raged Barbarian |
| b02.png | 隐秘弓箭手 | Archer（建筑大师基地版，页面：Archer/Builder Base） |
| b03.png | 巨人拳击手 | Boxer Giant |
| b04.png | 异变亡灵 | Beta Minion |
| b05.png | 炸弹兵 | Bomber |
| b06.png | 飞龙宝宝 | Baby Dragon（建筑大师基地版，页面：Baby Dragon/Builder Base） |
| b07.png | 加农炮战车 | Cannon Cart |
| b08.png | 暗夜女巫 | Night Witch |
| b09.png | 骷髅气球 | Drop Ship |
| b10.png | 雷霆皮卡 | Power P.E.K.K.A（曾用名 Super P.E.K.K.A） |
| b11.png | 野猪飞骑 | Hog Glider |

## 超级兵种卡牌（s01~s17）
| 文件名 | 卡牌名称 | Wiki 页面名（英文） |
| --- | --- | --- |
| s01.png | 超级野蛮人 | Super Barbarian |
| s02.png | 超级弓箭手 | Super Archer |
| s03.png | 超级巨人 | Super Giant |
| s04.png | 隐秘哥布林 | Sneaky Goblin |
| s05.png | 超级炸弹人 | Super Wall Breaker |
| s06.png | 火箭气球兵 | Rocket Balloon |
| s07.png | 超级法师 | Super Wizard |
| s08.png | 超级飞龙 | Super Dragon |
| s09.png | 地狱飞龙 | Inferno Dragon |
| s10.png | 超级矿工 | Super Miner |
| s11.png | 超级大雪怪 | Super Yeti |
| s12.png | 超级亡灵 | Super Minion |
| s13.png | 超级野猪骑士 | Super Hog Rider |
| s14.png | 超级瓦基丽武神 | Super Valkyrie |
| s15.png | 超级女巫 | Super Witch |
| s16.png | 寒冰猎犬 | Ice Hound |
| s17.png | 超级巨石投手 | Super Bowler |

# 完成标准（自查清单）
1. `public/images/cards/` 下恰好有 **60 张 PNG**，文件名与上表 card_id 完全一致（e01~e19、d01~d13、b01~b11、s01~s17），无多余、无缺失
2. 每张图片均为 **512×512** PNG，且单张 ≤ 1MB，内容为官方兵种立绘，**无水印、无AI痕迹**
3. 已确认没有残留旧的 `c01~c12` 等无关文件（如有可删除）
4. 向用户汇报：每张图片对应的 Wiki 来源页面、总大小（MB）、是否全部完成；如有未能完成的卡牌请列出卡牌ID和原因