/// Simple bilingual string table — no code generation needed.
/// Usage:  final s = ref.watch(stringsProvider);  s.dashboard
class S {
  final _M _m;
  const S._(this._m);

  // ignore: non_constant_identifier_names
  static S of(String lang) => S._(lang == 'zh' ? _zh : _en);

  // --- Home / tiles ---
  String get signalKHub  => _m['signalKHub']!;
  String get dashboard   => _m['dashboard']!;
  String get power       => _m['power']!;
  String get logbook     => _m['logbook']!;
  String get safety      => _m['safety']!;
  String get maintenance => _m['maintenance']!;
  String get weather     => _m['weather']!;
  String get tools       => _m['tools']!;
  String get settings    => _m['settings']!;

  // --- Status ---
  String get connected      => _m['connected']!;
  String get disconnected   => _m['disconnected']!;
  String get comingSoon     => _m['comingSoon']!;
  String get peers          => _m['peers']!;

  // --- Status bar ---
  String get sog   => _m['sog']!;
  String get cog   => _m['cog']!;
  String get depth => _m['depth']!;
  String get tws   => _m['tws']!;

  // --- MOB ---
  String get mob             => _m['mob']!;
  String get manOverboard    => _m['manOverboard']!;
  String get mobConfirmBody  => _m['mobConfirmBody']!;
  String get mobConfirm      => _m['mobConfirm']!;
  String get cancel          => _m['cancel']!;
  String get recover         => _m['recover']!;
  String get mobElapsed      => _m['mobElapsed']!;
  String get mobDistance     => _m['mobDistance']!;
  String get mobBearing      => _m['mobBearing']!;

  // --- Signal K ---
  String get signalKUrl     => _m['signalKUrl']!;
  String get connect        => _m['connect']!;
  String get disconnect     => _m['disconnect']!;
  String get liveData       => _m['liveData']!;

  // --- Dashboard ---
  String get speedSOG    => _m['speedSOG']!;
  String get courseC0G   => _m['courseC0G']!;
  String get heading     => _m['heading']!;
  String get trueWind    => _m['trueWind']!;
  String get apparentWind => _m['apparentWind']!;
  String get depthKeel   => _m['depthKeel']!;
  String get position    => _m['position']!;
  String get batteries   => _m['batteries']!;
  String get noData      => _m['noData']!;

  // --- Settings ---
  String get language         => _m['language']!;
  String get vesselName       => _m['vesselName']!;
  String get signalKSection   => _m['signalKSection']!;
  String get lanSync          => _m['lanSync']!;
  String get deviceRole       => _m['deviceRole']!;
  String get standalone       => _m['standalone']!;
  String get host             => _m['host']!;
  String get client           => _m['client']!;
  String get autoConnect      => _m['autoConnect']!;
  String get keepScreenOn     => _m['keepScreenOn']!;
  String get about            => _m['about']!;
  String get version          => _m['version']!;

  // --- Logbook ---
  String get addEntry    => _m['addEntry']!;
  String get noEntries   => _m['noEntries']!;
  String get departure   => _m['departure']!;
  String get arrival     => _m['arrival']!;
  String get waypoint    => _m['waypoint']!;
  String get manual      => _m['manual']!;

  // --- Maintenance ---
  String get addTask     => _m['addTask']!;
  String get noTasks     => _m['noTasks']!;
  String get overdue     => _m['overdue']!;
  String get markDone    => _m['markDone']!;
  String get dueIn       => _m['dueIn']!;
}

typedef _M = Map<String, String>;

const _en = <String, String>{
  'signalKHub':   'Signal K Hub',
  'dashboard':    'Dashboard',
  'power':        'Power',
  'logbook':      'Logbook',
  'safety':       'Safety',
  'maintenance':  'Maintenance',
  'weather':      'Weather',
  'tools':        'Tools',
  'settings':     'Settings',

  'connected':    'Connected',
  'disconnected': 'Disconnected',
  'comingSoon':   'Coming soon',
  'peers':        'peers',

  'sog':   'SOG',
  'cog':   'COG',
  'depth': 'DEPTH',
  'tws':   'TWS',

  'mob':            'MOB',
  'manOverboard':   'MAN OVERBOARD',
  'mobConfirmBody': 'Trigger a Man Overboard alert?\n\nThis will record your GPS position and notify all connected devices.',
  'mobConfirm':     'CONFIRM MOB',
  'cancel':         'Cancel',
  'recover':        'Mark Recovered',
  'mobElapsed':     'Elapsed',
  'mobDistance':    'Distance',
  'mobBearing':     'Bearing to MOB',

  'signalKUrl':    'Signal K URL',
  'connect':       'Connect',
  'disconnect':    'Disconnect',
  'liveData':      'Live Data',

  'speedSOG':      'Speed (SOG)',
  'courseC0G':     'Course (COG)',
  'heading':       'Heading',
  'trueWind':      'True Wind',
  'apparentWind':  'Apparent Wind',
  'depthKeel':     'Depth (keel)',
  'position':      'Position',
  'batteries':     'Batteries',
  'noData':        'No data',

  'language':       'Language',
  'vesselName':     'Vessel Name',
  'signalKSection': 'Signal K',
  'lanSync':        'LAN Sync',
  'deviceRole':     'Device Role',
  'standalone':     'Standalone',
  'host':           'Host (Master)',
  'client':         'Client',
  'autoConnect':    'Auto-connect on start',
  'keepScreenOn':   'Keep screen on',
  'about':          'About',
  'version':        'Version',

  'addEntry':  'Add Entry',
  'noEntries': 'No log entries yet',
  'departure': 'Departure',
  'arrival':   'Arrival',
  'waypoint':  'Waypoint',
  'manual':    'Note',

  'addTask':  'Add Task',
  'noTasks':  'No maintenance tasks',
  'overdue':  'Overdue',
  'markDone': 'Mark Done',
  'dueIn':    'Due in',
};

const _zh = <String, String>{
  'signalKHub':   'Signal K 枢纽',
  'dashboard':    '仪表盘',
  'power':        '电力管理',
  'logbook':      '航行日志',
  'safety':       '安全模块',
  'maintenance':  '维护记录',
  'weather':      '天气',
  'tools':        '工具集',
  'settings':     '设置',

  'connected':    '已连接',
  'disconnected': '未连接',
  'comingSoon':   '即将上线',
  'peers':        '设备',

  'sog':   '航速',
  'cog':   '航向',
  'depth': '水深',
  'tws':   '真风速',

  'mob':            'MOB',
  'manOverboard':   '人员落水',
  'mobConfirmBody': '触发人员落水警报？\n\n将记录当前 GPS 坐标并通知所有已连接设备。',
  'mobConfirm':     '确认落水警报',
  'cancel':         '取消',
  'recover':        '标记已救援',
  'mobElapsed':     '已过时间',
  'mobDistance':    '距离',
  'mobBearing':     '落水方位',

  'signalKUrl':    'Signal K 地址',
  'connect':       '连接',
  'disconnect':    '断开',
  'liveData':      '实时数据',

  'speedSOG':      '对地航速',
  'courseC0G':     '对地航向',
  'heading':       '船首向',
  'trueWind':      '真风',
  'apparentWind':  '视风',
  'depthKeel':     '龙骨水深',
  'position':      '位置',
  'batteries':     '电池',
  'noData':        '暂无数据',

  'language':       '语言',
  'vesselName':     '船名',
  'signalKSection': 'Signal K',
  'lanSync':        '局域网同步',
  'deviceRole':     '设备角色',
  'standalone':     '独立模式',
  'host':           '主机 (Host)',
  'client':         '客户端',
  'autoConnect':    '启动时自动连接',
  'keepScreenOn':   '保持屏幕常亮',
  'about':          '关于',
  'version':        '版本',

  'addEntry':  '添加记录',
  'noEntries': '暂无日志条目',
  'departure': '离港',
  'arrival':   '到港',
  'waypoint':  '航点',
  'manual':    '备注',

  'addTask':  '添加任务',
  'noTasks':  '暂无维护任务',
  'overdue':  '已逾期',
  'markDone': '标记完成',
  'dueIn':    '距到期',
};
