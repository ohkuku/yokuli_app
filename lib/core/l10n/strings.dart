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

  // --- Safety screen ---
  String get safetyTitle     => _m['safetyTitle']!;
  String get cancelMobTitle  => _m['cancelMobTitle']!;
  String get cancelMobBody   => _m['cancelMobBody']!;
  String get back            => _m['back']!;
  String get recovered       => _m['recovered']!;
  String get triggerMob      => _m['triggerMob']!;
  String get mobRecoveredBtn => _m['mobRecoveredBtn']!;
  String get alarmLabel      => _m['alarmLabel']!;

  // --- Signal K ---
  String get signalKUrl     => _m['signalKUrl']!;
  String get signalKHostLabel => _m['signalKHostLabel']!;
  String get signalKHostHint  => _m['signalKHostHint']!;
  String get signalKPortLabel => _m['signalKPortLabel']!;
  String get skServerSection  => _m['skServerSection']!;
  String get skAuthSection    => _m['skAuthSection']!;
  String get skAuthHint       => _m['skAuthHint']!;
  String get skOptionsSection => _m['skOptionsSection']!;
  String get skConnecting     => _m['skConnecting']!;
  String get autoConnectHint  => _m['autoConnectHint']!;
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
  String get save             => _m['save']!;
  String get settingsSaved    => _m['settingsSaved']!;
  String get lanSyncRestarted => _m['lanSyncRestarted']!;
  String get restartLanSync   => _m['restartLanSync']!;
  String get hostingStatus    => _m['hostingStatus']!;
  String get webModeLabel     => _m['webModeLabel']!;

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

  // --- Common actions ---
  String get add         => _m['add']!;
  String get addNote     => _m['addNote']!;
  String get enterNote   => _m['enterNote']!;
  String get enterMessage => _m['enterMessage']!;
  String get start       => _m['start']!;
  String get complete    => _m['complete']!;
  String get required    => _m['required']!;

  // --- Voyage ---
  String get voyage            => _m['voyage']!;
  String get endVoyage         => _m['endVoyage']!;
  String get endVoyageConfirm  => _m['endVoyageConfirm']!;
  String get activeVoyageLabel => _m['activeVoyageLabel']!;
  String get quickLog          => _m['quickLog']!;
  String get noActiveVoyage    => _m['noActiveVoyage']!;
  String get startVoyageHint   => _m['startVoyageHint']!;
  String get startVoyage       => _m['startVoyage']!;
  String get history           => _m['history']!;
  String get noVoyageHistory   => _m['noVoyageHistory']!;
  String get elapsed           => _m['elapsed']!;
  String get voyageSourceAuto   => _m['voyageSourceAuto']!;
  String get voyageSourceManual => _m['voyageSourceManual']!;
  String get voyageActive      => _m['voyageActive']!;

  // --- Tasks ---
  String get tasksTitle        => _m['tasksTitle']!;
  String get tabActive         => _m['tabActive']!;
  String get tabTemplates      => _m['tabTemplates']!;
  String get noActiveTasks     => _m['noActiveTasks']!;
  String get startFromTemplates => _m['startFromTemplates']!;
  String get noTemplates       => _m['noTemplates']!;
  String get taskNotFound      => _m['taskNotFound']!;
  String get createIssueTitle  => _m['createIssueTitle']!;
  String get issueTitleLabel   => _m['issueTitleLabel']!;
  String get taskStarted       => _m['taskStarted']!;
  String get builtIn           => _m['builtIn']!;
  String get doneLabel         => _m['doneLabel']!;
  String get issueLabel        => _m['issueLabel']!;
  String get issueBadge        => _m['issueBadge']!;
  String get items             => _m['items']!;
  // Task category labels
  String get catPreDeparture   => _m['catPreDeparture']!;
  String get catPostArrival    => _m['catPostArrival']!;
  String get catSafety         => _m['catSafety']!;
  String get catPeriodic       => _m['catPeriodic']!;
  String get catCustom         => _m['catCustom']!;
  // Task status labels
  String get statusOpen        => _m['statusOpen']!;
  String get statusInProgress  => _m['statusInProgress']!;
  String get statusDone        => _m['statusDone']!;
  String get statusSkipped     => _m['statusSkipped']!;

  // --- Issues ---
  String get issuesTitle       => _m['issuesTitle']!;
  String get tabOpen           => _m['tabOpen']!;
  String get tabResolved       => _m['tabResolved']!;
  String get noOpenIssues      => _m['noOpenIssues']!;
  String get noOpenIssuesHint  => _m['noOpenIssuesHint']!;
  String get noResolvedIssues  => _m['noResolvedIssues']!;
  String get statusSection     => _m['statusSection']!;
  String get notesSection      => _m['notesSection']!;
  String get noNotes           => _m['noNotes']!;
  String get newIssue          => _m['newIssue']!;
  String get severityLabel     => _m['severityLabel']!;
  String get low               => _m['low']!;
  String get medium            => _m['medium']!;
  String get high              => _m['high']!;
  // Issue status labels
  String get issueOpen         => _m['issueOpen']!;
  String get issueDoing        => _m['issueDoing']!;
  String get issueBlocked      => _m['issueBlocked']!;
  String get issueResolved     => _m['issueResolved']!;
  // Issue source labels
  String get sourceChecklist   => _m['sourceChecklist']!;
  String get sourceManual      => _m['sourceManual']!;
  String get sourceAlarm       => _m['sourceAlarm']!;

  // --- Log ---
  String get logTitle          => _m['logTitle']!;
  String get addLogEntry       => _m['addLogEntry']!;
  String get noLogEntries      => _m['noLogEntries']!;
  String get noLogEntriesHint  => _m['noLogEntriesHint']!;
  // Log filter labels
  String get filterAll         => _m['filterAll']!;
  String get filterNavigation  => _m['filterNavigation']!;
  String get filterPower       => _m['filterPower']!;
  String get filterAis         => _m['filterAis']!;
  String get filterManual      => _m['filterManual']!;
  String get filterSystem      => _m['filterSystem']!;
  String get filterAlarm       => _m['filterAlarm']!;
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

  'safetyTitle':    'Safety',
  'cancelMobTitle': 'Cancel MOB Alert?',
  'cancelMobBody':  'Confirm person has been recovered.',
  'back':           'Back',
  'recovered':      'Recovered',
  'triggerMob':     'TRIGGER MOB ALERT',
  'mobRecoveredBtn': 'MOB RECOVERED — Cancel Alert',
  'alarmLabel':     'ALARM',

  'signalKUrl':       'Signal K URL',
  'signalKHostLabel': 'Host / Address',
  'signalKHostHint':  '192.168.1.10 or signalk.local',
  'signalKPortLabel': 'Port',
  'skServerSection':  'SERVER',
  'skAuthSection':    'AUTHENTICATION',
  'skAuthHint':       '(leave blank if not required)',
  'skOptionsSection': 'OPTIONS',
  'skConnecting':     'Connecting…',
  'autoConnectHint':  'Connect to Signal K automatically when the app launches',
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
  'save':           'Save',
  'settingsSaved':  'Settings saved',
  'lanSyncRestarted': 'LAN sync restarted',
  'restartLanSync': 'Restart LAN sync',
  'hostingStatus':  'This device is hosting',
  'webModeLabel':   'Web Mode',

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

  'add':          'Add',
  'addNote':      'Add Note',
  'enterNote':    'Enter note…',
  'enterMessage': 'Enter message…',
  'start':        'Start',
  'complete':     'Complete',
  'required':     'Required',

  'voyage':            'Voyage',
  'endVoyage':         'End Voyage',
  'endVoyageConfirm':  'Are you sure you want to end the current voyage?',
  'activeVoyageLabel': 'ACTIVE VOYAGE',
  'quickLog':          'QUICK LOG',
  'noActiveVoyage':    'No active voyage',
  'startVoyageHint':   'Start a voyage to track your trip and log events.',
  'startVoyage':       'Start Voyage',
  'history':           'HISTORY',
  'noVoyageHistory':   'No voyage history yet.',
  'elapsed':           'elapsed',
  'voyageSourceAuto':  'AUTO',
  'voyageSourceManual': 'MANUAL',
  'voyageActive':      'active',

  'tasksTitle':         'Tasks',
  'tabActive':          'Active',
  'tabTemplates':       'Templates',
  'noActiveTasks':      'No active tasks',
  'startFromTemplates': 'Start one from the Templates tab',
  'noTemplates':        'No templates available.',
  'taskNotFound':       'Task not found.',
  'createIssueTitle':   'Create Issue',
  'issueTitleLabel':    'Issue title',
  'taskStarted':        'Task started',
  'builtIn':            'BUILT-IN',
  'doneLabel':          'Done',
  'issueLabel':         'Issue',
  'issueBadge':         'ISSUE',
  'items':              'items',
  'catPreDeparture':    'Pre-Departure',
  'catPostArrival':     'Post-Arrival',
  'catSafety':          'Safety',
  'catPeriodic':        'Periodic',
  'catCustom':          'Custom',
  'statusOpen':         'Open',
  'statusInProgress':   'In Progress',
  'statusDone':         'Done',
  'statusSkipped':      'Skipped',

  'issuesTitle':        'Issues',
  'tabOpen':            'Open',
  'tabResolved':        'Resolved',
  'noOpenIssues':       'No open issues',
  'noOpenIssuesHint':   'All clear — tap + to log a new issue.',
  'noResolvedIssues':   'No resolved issues yet',
  'statusSection':      'STATUS',
  'notesSection':       'NOTES',
  'noNotes':            'No notes yet.',
  'newIssue':           'New Issue',
  'severityLabel':      'SEVERITY',
  'low':                'Low',
  'medium':             'Medium',
  'high':               'High',
  'issueOpen':          'Open',
  'issueDoing':         'In Progress',
  'issueBlocked':       'Blocked',
  'issueResolved':      'Resolved',
  'sourceChecklist':    'Checklist',
  'sourceManual':       'Manual',
  'sourceAlarm':        'Alarm',

  'logTitle':           'Log',
  'addLogEntry':        'Add Log Entry',
  'noLogEntries':       'No log entries yet',
  'noLogEntriesHint':   'Events and manual entries will appear here.',
  'filterAll':          'All',
  'filterNavigation':   'Navigation',
  'filterPower':        'Power',
  'filterAis':          'AIS',
  'filterManual':       'Manual',
  'filterSystem':       'System',
  'filterAlarm':        'Alarm',
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

  'safetyTitle':    '安全模块',
  'cancelMobTitle': '取消落水警报？',
  'cancelMobBody':  '确认人员已被救援。',
  'back':           '返回',
  'recovered':      '已救援',
  'triggerMob':     '触发落水警报',
  'mobRecoveredBtn': '人员已救援 — 取消警报',
  'alarmLabel':     '警报',

  'signalKUrl':       'Signal K 地址',
  'signalKHostLabel': '主机 / 地址',
  'signalKHostHint':  '192.168.1.10 或 signalk.local',
  'signalKPortLabel': '端口',
  'skServerSection':  '服务器',
  'skAuthSection':    '认证',
  'skAuthHint':       '（无需认证可留空）',
  'skOptionsSection': '选项',
  'skConnecting':     '连接中…',
  'autoConnectHint':  '应用启动时自动连接到 Signal K',
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
  'save':           '保存',
  'settingsSaved':  '设置已保存',
  'lanSyncRestarted': '局域网同步已重启',
  'restartLanSync': '重启局域网同步',
  'hostingStatus':  '本设备正在主机模式运行',
  'webModeLabel':   'Web 模式',

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

  'add':          '添加',
  'addNote':      '添加备注',
  'enterNote':    '输入备注…',
  'enterMessage': '输入内容…',
  'start':        '开始',
  'complete':     '完成',
  'required':     '必填',

  'voyage':            '航行记录',
  'endVoyage':         '结束航行',
  'endVoyageConfirm':  '确认结束当前航行吗？',
  'activeVoyageLabel': '当前航行',
  'quickLog':          '快速记录',
  'noActiveVoyage':    '当前无航行',
  'startVoyageHint':   '开始航行以追踪行程并记录事件。',
  'startVoyage':       '开始航行',
  'history':           '历史记录',
  'noVoyageHistory':   '暂无航行记录。',
  'elapsed':           '已用时',
  'voyageSourceAuto':  '自动',
  'voyageSourceManual': '手动',
  'voyageActive':      '进行中',

  'tasksTitle':         '任务',
  'tabActive':          '进行中',
  'tabTemplates':       '模板',
  'noActiveTasks':      '暂无进行中的任务',
  'startFromTemplates': '从模板标签页开始一个任务',
  'noTemplates':        '暂无模板。',
  'taskNotFound':       '任务未找到。',
  'createIssueTitle':   '创建问题',
  'issueTitleLabel':    '问题标题',
  'taskStarted':        '任务已开始',
  'builtIn':            '内置',
  'doneLabel':          '完成',
  'issueLabel':         '问题',
  'issueBadge':         '问题',
  'items':              '项',
  'catPreDeparture':    '出发前检查',
  'catPostArrival':     '到达后检查',
  'catSafety':          '安全检查',
  'catPeriodic':        '定期维护',
  'catCustom':          '自定义',
  'statusOpen':         '未开始',
  'statusInProgress':   '进行中',
  'statusDone':         '已完成',
  'statusSkipped':      '已跳过',

  'issuesTitle':        '问题列表',
  'tabOpen':            '未解决',
  'tabResolved':        '已解决',
  'noOpenIssues':       '暂无未解决问题',
  'noOpenIssuesHint':   '一切正常 — 点击 + 记录新问题。',
  'noResolvedIssues':   '暂无已解决问题',
  'statusSection':      '状态',
  'notesSection':       '备注',
  'noNotes':            '暂无备注。',
  'newIssue':           '新建问题',
  'severityLabel':      '严重程度',
  'low':                '低',
  'medium':             '中',
  'high':               '高',
  'issueOpen':          '未处理',
  'issueDoing':         '处理中',
  'issueBlocked':       '受阻',
  'issueResolved':      '已解决',
  'sourceChecklist':    '检查单',
  'sourceManual':       '手动',
  'sourceAlarm':        '警报',

  'logTitle':           '日志',
  'addLogEntry':        '添加日志',
  'noLogEntries':       '暂无日志条目',
  'noLogEntriesHint':   '事件和手动条目将显示在此处。',
  'filterAll':          '全部',
  'filterNavigation':   '导航',
  'filterPower':        '电力',
  'filterAis':          'AIS',
  'filterManual':       '手动',
  'filterSystem':       '系统',
  'filterAlarm':        '警报',
};
