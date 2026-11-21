/// Canonical Trigger Ownership & Precedence Ladder Registry.
///
/// Implements `docs/product-spec.md` §1, §2 & §5:
///   1. "One meaning, one trigger" — no two distinct rules may claim the same
///      normalized trigger signature.
///   2. Machine-checked by `test/trigger_registry_test.dart`: every rule carries
///      positive, boundary, and non-trigger assertions so future syntax additions
///      cannot silently hijack an existing keyword or operator.
library;

class TriggerRule {
  /// Stable identifier for explainability and collision diagnostics.
  final String id;

  /// Precedence ladder tier (`1` highest .. `11` lowest, matching product-spec).
  final int tier;

  /// Human-readable description of what the rule owns.
  final String summary;

  /// Canonical trigger tokens/shapes exclusively owned by this rule.
  final List<String> triggers;

  /// Representative input that MUST be answered by this rule.
  final String positiveExample;

  /// Expected display answer at reference date `2026-10-31T09:00` (USD=1, HKD=7.8).
  /// Null only for comment/heading rules that intentionally emit no answer.
  final String? expectedDisplay;

  /// Optional multi-line context preceding [positiveExample] (e.g. for totals).
  final List<String> contextLines;

  /// Input that resembles this rule's neighbourhood and MUST stay unanswered
  /// (`display == null`), guarding "No answer beats a wrong answer".
  final String? negativeExample;

  const TriggerRule({
    required this.id,
    required this.tier,
    required this.summary,
    required this.triggers,
    required this.positiveExample,
    this.expectedDisplay,
    this.contextLines = const [],
    this.negativeExample,
  });
}

const List<TriggerRule> triggerRegistry = [
  // Tier 1: Comments, Headings & Blank Lines
  TriggerRule(
    id: 'heading',
    tier: 1,
    summary: 'Section heading starting with `# ` resets section & subtotal bounds',
    triggers: ['^# '],
    positiveExample: '# Monthly Budget',
    expectedDisplay: null,
  ),
  TriggerRule(
    id: 'draft_comment',
    tier: 1,
    summary: 'Draft line starting with `//` is greyed and never evaluated',
    triggers: ['^//'],
    positiveExample: '// 2000 + 3000',
    expectedDisplay: null,
  ),

  // Tier 2: Variable Declaration & Single-Unknown Equation Solver
  TriggerRule(
    id: 'solve_unknown',
    tier: 2,
    summary: 'Single-unknown linear equation with `?` or `?%` across `=`',
    triggers: ['? =', '= ?', '?% ='],
    positiveExample: '? * 30% = 1290',
    expectedDisplay: '4,300',
    negativeExample: '? * ? = 9',
  ),
  TriggerRule(
    id: 'variable_assign',
    tier: 2,
    summary: 'Variable binding `name = expr` (wins over built-in aggregates)',
    triggers: ['name = expr'],
    positiveExample: 'rent = 2500',
    expectedDisplay: '2,500',
  ),

  // Tier 3: Explicit Function Calls
  TriggerRule(
    id: 'function_call',
    tier: 3,
    summary: 'Built-in math functions (`sqrt`, `round`, `sin`, `min`, `max`, `pow`, `root`)',
    triggers: [
      'sqrt()',
      'cbrt()',
      'abs()',
      'log()',
      'ln()',
      'exp()',
      'sin()',
      'cos()',
      'tan()',
      'round()',
      'ceil()',
      'floor()',
      'fact()',
      'min()',
      'max()',
      'pow()',
      'root()',
    ],
    positiveExample: 'round(3.14159, 2)',
    expectedDisplay: '3.14',
  ),

  // Tier 4: Explicit Unit & Currency Conversion
  TriggerRule(
    id: 'unit_convert',
    tier: 4,
    summary: 'Explicit conversion to a known unit or currency',
    triggers: ['in <unit>', 'to <unit>', 'as <unit>', 'into <unit>', '-> <unit>', '兌 <ccy>', '換成 <ccy>'],
    positiveExample: '100 USD in HKD',
    expectedDisplay: r'HK$780.00',
    negativeExample: '10500 in sci',
  ),

  // Tier 5: Structured Phrases (unambiguous multi-word frames)
  TriggerRule(
    id: 'rule_of_three',
    tier: 5,
    summary: 'Proportional rule of three (`A is to B as C is to what`)',
    triggers: ['is to ... as ... is to what'],
    positiveExample: '9 is to 16 as 27 is to what',
    expectedDisplay: '48',
  ),
  TriggerRule(
    id: 'conditional_if',
    tier: 5,
    summary: 'Conditional expression (`if <cond> then <a> else <b>`)',
    triggers: ['if ... then ... else'],
    positiveExample: 'if 5 > 3 then 10 else 20',
    expectedDisplay: '10',
  ),
  TriggerRule(
    id: 'percent_off',
    tier: 5,
    summary: 'English retail discount (`X% off Y`)',
    triggers: ['% off'],
    positiveExample: '25% off 160',
    expectedDisplay: '120',
    negativeExample: '20%オフ 100',
  ),
  TriggerRule(
    id: 'zh_discount',
    tier: 5,
    summary: 'Chinese retail discount (`打八折`, `八五折`, refuses Japanese `割引`)',
    triggers: ['打N折', 'N折'],
    positiveExample: '打八折 480',
    expectedDisplay: '384',
    negativeExample: '2割引 100',
  ),
  TriggerRule(
    id: 'zh_surcharge',
    tier: 5,
    summary: 'Hong Kong 10% service charge (`加一`) and Chinese tenths (`加N成` / `減N成`)',
    triggers: ['加一', '加N成', '減N成'],
    positiveExample: '480 加一',
    expectedDisplay: '528',
  ),
  TriggerRule(
    id: 'percent_question',
    tier: 5,
    summary: 'Inverse percentage questions (`X is what % of Y`, `X% of what is Y`, `是…的百分之幾`)',
    triggers: ['is what % of', '% of what is', '是...的百分之幾', '的幾多是'],
    positiveExample: '20 is what % of 80',
    expectedDisplay: '25%',
  ),
  TriggerRule(
    id: 'percent_change',
    tier: 5,
    summary: 'Relative percentage change (`from A to B in %`, `change from A to B`, `A 到 B 升跌`)',
    triggers: ['from ... to ... in %', 'change from ... to', '到 ... 升跌'],
    positiveExample: 'from 80 to 100 in %',
    expectedDisplay: '25%',
  ),
  TriggerRule(
    id: 'compound_interest',
    tier: 5,
    summary: 'Compound interest (`compound interest P at R% for N years`)',
    triggers: ['compound interest ... at ... for'],
    positiveExample: 'compound interest 1000 at 10% for 2 years',
    expectedDisplay: '1,210',
  ),
  TriggerRule(
    id: 'bill_split',
    tier: 5,
    summary: 'Equal bill splitting (`分帳 N 人`, `夾錢`, `攤分`, `split N 人`, `割り勘`, `더치페이`)',
    triggers: ['分帳', '夾錢', '攤分', '割り勘', '더치페이', '엔빵'],
    positiveExample: r'$300 分 2 人',
    expectedDisplay: r'$150.00',
  ),
  TriggerRule(
    id: 'annualise_rate',
    tier: 5,
    summary: 'Annualise daily/weekly/monthly rate (`X/day is what per year`)',
    triggers: ['/day is what per year', '/week is what per year', '/month is what per year'],
    positiveExample: r'$30/day is what per year',
    expectedDisplay: r'$10,950.00',
    negativeExample: r'$30/day is what per week',
  ),

  // Tier 6: Section & Sheet Aggregations
  TriggerRule(
    id: 'section_subtotal',
    tier: 6,
    summary: 'Run-on subtotal since previous `subtotal` or `# heading`',
    triggers: ['subtotal', '小計', '小计'],
    contextLines: ['100', '200'],
    positiveExample: 'subtotal',
    expectedDisplay: '300',
  ),
  TriggerRule(
    id: 'section_aggregate',
    tier: 6,
    summary: 'Whole-section leaf aggregation (`sum`, `total`, `average`, `avg`, `count`, `min`, `max`)',
    triggers: ['sum', 'total', 'average', 'avg', 'count', 'min', 'max'],
    contextLines: ['# S', '100', '200', 'subtotal', '50'],
    positiveExample: 'sum',
    expectedDisplay: '350',
  ),
  TriggerRule(
    id: 'grand_total',
    tier: 6,
    summary: 'Whole-sheet leaf grand total grouped by unit/currency',
    triggers: ['grand total', '合共', '總共', '總計', '總和', '合计', '总共', '总计', '总和', '加埋', '全部'],
    contextLines: ['# A', '100', '# B', '250'],
    positiveExample: '合共',
    expectedDisplay: '350',
  ),

  // Tier 7: Tag Aggregations
  TriggerRule(
    id: 'tag_total',
    tier: 7,
    summary: 'Sum of all leaf lines carrying `#tag` anywhere on the sheet',
    triggers: ['total of #tag', 'sum of #tag', 'subtotal of #tag'],
    contextLines: ['flights 4000 #trip', 'hotel 2000 #trip'],
    positiveExample: 'total of #trip',
    expectedDisplay: '6,000',
  ),

  // Tier 8: Dates, Durations & Time Zones
  TriggerRule(
    id: 'date_timezone',
    tier: 8,
    summary: 'Offline dates, workdays, date gaps, spoken durations, and IANA time zones',
    triggers: ['today', 'tomorrow', 'yesterday', 'workdays', 'days between', 'days until', '<date> in <zone>'],
    positiveExample: '2026-01-30 + 3 workdays',
    expectedDisplay: '4 February 2026',
    negativeExample: '2026-02-30',
  ),

  // Tier 9 & 10: General Expressions & Leading-Prose Skip
  TriggerRule(
    id: 'arithmetic_expr',
    tier: 9,
    summary: 'Arithmetic, percentages, remainders (`%` before number), scale words, references (`prev`, `line N`)',
    triggers: ['+', '-', '*', '/', '^', '%', 'mod', 'x', '加', '減', '乘', '除', '餘', 'prev', 'line N'],
    positiveExample: '買嘢 4300 x 30%',
    expectedDisplay: '1,290',
    negativeExample: '4300 X 30%',
  ),

  // Tier 11: Lone Number in Prose
  TriggerRule(
    id: 'lone_number',
    tier: 11,
    summary: 'Prose with a single number and no stray operators (`午餐 120`)',
    triggers: ['<prose> <number>'],
    positiveExample: '午餐 120',
    expectedDisplay: '120',
    negativeExample: 'rent * 12',
  ),
];
