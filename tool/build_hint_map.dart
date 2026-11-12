// dart run tool/build_hint_map.dart
import 'dart:convert';
import 'dart:io';

/// Character-level hints for exact duplicate [keyword] groups.
const hintsByKeywordAndChar = <String, Map<String, String>>{
  'advance': {'進': 'move forward', '晋': 'dynasty / promote'},
  'all': {'皆': 'everyone', '惣': 'all / total'},
  'angle': {'角': 'corner / horn', '稜': 'edge / facet'},
  'back': {'背': 'one\'s back', '裏': 'reverse side'},
  'ball': {'球': 'sphere / ball', '鞠': 'kickball'},
  'barbarian': {'胡': 'barbarian west', '蛮': 'savage / barbarian'},
  'blue': {'青': 'blue / green', '碧': 'jade blue', '蒼': 'pale blue'},
  'boil': {'湧': 'well up', '煮': 'cook / boil'},
  'bright': {'明': 'bright / clear', '熙': 'prosper / shine'},
  'burn': {'燃': 'burn / ignite', '燎': 'blaze / kindle'},
  'camp': {'営': 'manage / camp', '陣': 'battle camp'},
  'cedar': {'杉': 'cedar', '檀': 'sandalwood'},
  'chief': {'伯': 'chief / count', '孟': 'eldest / chief'},
  'clear': {
    '亮': 'bright clear',
    '冴': 'sharp / frosty',
    '晃': 'dazzling light',
    '晟': 'bright prosper',
    '瞭': 'clear sight',
  },
  'cold': {'寒': 'cold weather', '凜': 'biting cold'},
  'collar': {'衿': 'collar / neck', '襟': 'lapel / collar'},
  'commonplace': {'凡': 'mediocre', '庸': 'commonplace'},
  'congratulations': {'瑞': 'auspicious sign', '賀': 'congratulate'},
  'consider': {'考': 'think / consider', '惟': 'ponder / only'},
  'consult with': {'詢': 'inquire', '諮': 'consult / ask'},
  'contain': {'容': 'contain / form', '含': 'hold in mouth'},
  'cord': {'緒': 'cord / beginning', '索': 'rope / search'},
  'correct': {'正': 'correct / right', '匡': 'correct / aid'},
  'daybreak': {'旦': 'dawn / morning', '暁': 'daybreak / aware'},
  'design': {'柄': 'pattern / design', '綾': 'damask / design'},
  'distant': {'遠': 'far / distant', '遼': 'distant / remote'},
  'distribute': {'配': 'distribute', '頒': 'deliver / award'},
  'do': {'為': 'do / act for', '致': 'cause / do'},
  'ear': {'耳': 'ear organ', '穂': 'grain ear'},
  'eaves': {'宇': 'eaves / roof', '軒': 'eaves / porch'},
  'end': {'終': 'end / finish', '末': 'tip / end', '竣': 'complete project'},
  'endure': {'凌': 'endure / surpass', '忍': 'endure / ninja'},
  'evening': {'夕': 'evening dusk', '暮': 'sunset / dusk'},
  'excuse': {'免': 'excuse / exempt', '恕': 'forgive / excuse'},
  'emulate': {'倣': 'emulate / imitate', '競': 'compete / rival'},
  'exist': {'在': 'exist / be at', '存': 'exist / save'},
  'fear': {'恐': 'fear / afraid', '虞': 'fear / concern'},
  'feelings': {'情': 'feelings / passion', '懐': 'feelings / pocket'},
  'five': {'五': 'number five', '伍': 'five / troop'},
  'gauze': {'紗': 'gauze / yarn', '羅': 'gauze / net'},
  'gentleman': {'士': 'samurai / scholar', '紳': 'gentleman'},
  'give': {'呉': 'give / Wu', '施': 'bestow / apply'},
  'go': {'行': 'go / act', '碁': 'go game'},
  'grant': {'叶': 'grant / come true', '賜': 'bestow / gift'},
  'green': {'緑': 'green', '翠': 'jade green'},
  'happiness': {'幸': 'happiness / luck', '倖': 'happiness', '禎': 'blessing / good omen'},
  'harvest': {'稔': 'ripen / harvest', '穫': 'harvest crop'},
  'help': {
    '助': 'help / assist',
    '丞': 'vice-minister',
    '佑': 'divine help',
    '祐': 'divine protection',
    '輔': 'assist / supplement',
  },
  'high': {'喬': 'tall / lofty', '尭': 'high / sage', '峻': 'steep / high'},
  'idea': {'意': 'idea / mind', '想': 'think / concept'},
  'jasmine': {'茉': 'jasmine plant', '莉': 'white jasmine'},
  'jewel': {'玉': 'jewel / ball', '琳': 'gem / jade'},
  'large': {'碩': 'large / great', '紘': 'large / scale'},
  'level': {'均': 'equal / level', '庄': 'manor / level'},
  'lotus': {'芙': 'lotus flower', '蓉': 'lotus / hibiscus', '蓮': 'lotus'},
  'medicine': {'医': 'doctor / heal', '薬': 'medicine / drug'},
  'meet': {'会': 'meet / society', '遇': 'encounter / treat'},
  'morning': {'朝': 'morning', '晨': 'early morning'},
  'pass through': {'通': 'pass through', '亨': 'pass through / prosper'},
  'peak': {'岳': 'mountain peak', '嶺': 'ridge / peak'},
  'picture': {'画': 'draw / picture', '絵': 'picture / painting'},
  'pinch': {'挟': 'pinch / sandwich', '摘': 'pick / pluck'},
  'place': {'場': 'place / field', '所': 'place / particle'},
  'plum': {'李': 'plum tree', '梅': 'plum blossom'},
  'polish': {'研': 'polish / study', '琢': 'polish gem', '瑳': 'polish / shine'},
  'pure': {'清': 'pure / clean', '淳': 'pure / simple'},
  'rare': {'珍': 'rare / precious', '稀': 'sparse / rare'},
  'raise': {'挙': 'raise / action', '揚': 'raise / hoist'},
  'refreshing': {'涼': 'cool refreshing', '爽': 'refreshing / clear'},
  'refined': {'精': 'refined / spirit', '彬': 'refined / literary'},
  'respect': {'恭': 'respect / polite', '欽': 'respect / revere'},
  'return': {'戻': 'return back', '返': 'return / give back'},
  'ride': {'乗': 'ride / board', '載': 'load / ride'},
  'river': {'川': 'river', '河': 'river / stream'},
  'run': {'走': 'run', '奔': 'run / rush'},
  'sand': {'砂': 'sand', '沙': 'sand / granule'},
  'shine': {'暉': 'sunshine', '燿': 'shine brightly', '耀': 'dazzle / shine'},
  'shop': {'屋': 'shop / house', '店': 'store', '舗': 'shopfront'},
  'slope': {'阪': 'slope / Osaka', '坂': 'slope / hill'},
  'song': {'歌': 'song / sing', '唄': 'ballad / song', '謡': 'chant / ballad'},
  'spring': {'春': 'spring season', '泉': 'spring water'},
  'stand': {'台': 'stand / platform', '立': 'stand up'},
  'stretch': {'張': 'stretch / spread', '暢': 'unobstructed'},
  'star': {'星': 'star', '奎': 'constellation'},
  'strong': {
    '強': 'strong / force',
    '侃': 'outspoken',
    '勁': 'vigorous',
    '毅': 'willpower',
  },
  'summit': {'頂': 'summit / top', '峰': 'peak / summit'},
  'swamp': {'沢': 'swamp / marsh', '皐': 'marsh / shore'},
  'thread': {'糸': 'thread', '綸': 'thread / policy'},
  'thing': {'事': 'matter / affair', '物': 'thing / object'},
  'thick': {'太': 'thick / fat', '厚': 'thick / kind'},
  'turn': {'転': 'turn / roll', '番': 'turn / number'},
  'un-': {'未': 'not yet', '非': 'wrong / not'},
  'use': {'使': 'use / envoy', '用': 'use / employ'},
  'victory': {'勝': 'win / victory', '捷': 'victory / swift'},
  'village': {'村': 'village', '邑': 'village / town'},
  'warehouse': {'庫': 'warehouse', '倉': 'storehouse'},
  'white': {'白': 'white', '皓': 'bright white'},
  'wide': {'広': 'wide', '宏': 'wide / grand'},
  'willow': {'柳': 'willow', '楊': 'poplar / willow'},
  'wise': {'怜': 'wise / clever', '慧': 'wise / wisdom', '聡': 'wise / acute'},
  'world': {'世': 'generation / era', '界': 'boundary / realm'},
  'woods': {'林': 'grove / woods', '杜': 'woods / grove'},
  'peaceful': {'泰': 'peaceful / peace', '靖': 'peaceful / calm'},
};

/// Extra hints for cross-keyword similar-concept clusters.
const similarConceptHints = <String, String>{
  'n5-034': 'soil / ground', // 土 earth
  'n4-036': 'land / location', // 地 ground — id check needed
  'n1-0205': 'soil / earth',
  'n2-349': 'land / continent',
  'n4-015': 'origin / source', // 元
  'n2-153': 'plant root',
  'n1-0639': 'water source',
  'n4-094': 'sea / ocean',
  'n4-093': 'open ocean',
  'n5-011': 'individual person',
  'n3-204': 'populace / nation',
  'n5-040': 'school study',
  'n4-123': 'practice / learn',
  'n4-133': 'say / state',
  'n5-070': 'talk / speak',
  'n4-149': 'way / road',
  'n3-318': 'street path',
  'n5-058': 'energy / mood',
  'n1-1176': 'spirits / sacred',
  'n1-1212': 'soul / spirit',
  'n3-274': 'physical beauty',
  'n1-1228': 'lovely / graceful',
  'n1-0479': 'beautiful pattern',
  'n5-069': 'see / look',
  'n1-0999': 'inspect / view',
  'n3-296': 'observe / outlook',
  'n4-043': 'nighttime',
  'n4-132': 'parent / family',
  'n5-061': 'father parent',
  'n5-056': 'mother parent',
  'n5-062': 'life / birth',
  'n4-010': 'live / dwell',
  'n3-146': 'emotion / feel',
  'n5-051': 'tree / wood',
  'n2-156': 'forest / dense woods',
  'n3-361': 'head / chief',
  'n3-363': 'face / visage',
};

void main() {
  final dupes =
      jsonDecode(File('tool/dupe_cards.json').readAsStringSync()) as List;
  final hints = <String, String>{...similarConceptHints};

  final missing = <String>[];

  for (final raw in dupes) {
    final id = raw['id'] as String;
    final char = raw['character'] as String;
    final kw = raw['keyword'] as String;
  final group = hintsByKeywordAndChar[kw];
    if (group != null && group.containsKey(char)) {
      hints[id] = group[char]!;
    } else if (!hints.containsKey(id)) {
      missing.add('$id $char keyword=$kw');
    }
  }

  stderr.writeln('Hints: ${hints.length}, missing: ${missing.length}');
  for (final m in missing) {
    stderr.writeln('  MISSING: $m');
  }

  File('tool/disambiguation_hints.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(hints));
}
