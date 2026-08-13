/** 卡牌种类定义（与数据库 cards.category 对应） */
export const CATEGORIES = [
  { key: 'elixir',        label: '圣水卡牌',         short: '圣水' },
  { key: 'dark_elixir',   label: '暗黑重油卡牌',     short: '暗黑重油' },
  { key: 'builder_base',  label: '建筑大师基地卡牌', short: '建筑大师' },
  { key: 'super_troop',   label: '超级兵种卡牌',     short: '超级兵种' },
];

export const CATEGORY_MAP = Object.fromEntries(CATEGORIES.map((c) => [c.key, c]));

export const categoryLabel = (key) => CATEGORY_MAP[key]?.label ?? key;
export const categoryShort = (key) => CATEGORY_MAP[key]?.short ?? key;