// All UI strings for EN and KO.
// Access via: ref.watch(appStringsProvider)

class AppStrings {
  final String locale;

  // ── General ──────────────────────────────────────────────────────────────
  final String appName;
  final String appTagline;
  final String cancel;
  final String confirm;
  final String today;
  final String yesterday;
  final String daysAgo;
  final String seeAll;
  final String again;
  final String back;

  // ── Nav ──────────────────────────────────────────────────────────────────
  final String navHome;
  final String navCalendar;
  final String navWorkout;
  final String navReport;
  final String navProfile;
  final String calendar;
  final String calendarComingSoon;

  // ── Auth ─────────────────────────────────────────────────────────────────
  final String welcomeBack;
  final String createAccount;
  final String signIn;
  final String signUp;
  final String email;
  final String password;
  final String fullName;
  final String alreadyHaveAccount;
  final String noAccount;
  final String poweredBy;
  final String minEightChars;
  final String nameRequired;
  final String validEmail;
  final String signInSubtitle;
  final String signUpSubtitle;
  final String username;
  final String confirmPassword;
  final String checkDuplicate;
  final String duplicateAvailable;
  final String duplicateTaken;
  final String duplicateCheckRequired;
  final String gender;
  final String male;
  final String female;
  final String heightCm;
  final String weightKg;
  final String workoutGoal;
  final String goalDiet;
  final String goalStrength;
  final String goalPosture;
  final String passwordMismatch;
  final String idRequired;
  final String accountInfo;
  final String personalInfo;
  final String bodyStats;
  final String required;

  // ── Home ─────────────────────────────────────────────────────────────────
  final String greetingMorning;
  final String greetingAfternoon;
  final String greetingEvening;
  final String todaySummary;
  final String workouts;
  final String totalReps;
  final String activeTime;
  final String avgScore;
  final String readyToTrain;
  final String aiRealtime;
  final String streak;
  final String recentWorkouts;
  final String exercises;
  final String keepChain;
  final String dayStreak;
  final String myGoal;

  // ── Exercise Selection ───────────────────────────────────────────────────
  final String selectExercise;
  final String chooseExercise;
  final String aiTrackForm;
  final String configureWorkout;
  final String repsPerSet;
  final String durationSeconds;
  final String sets;
  final String start;
  final String beginner;
  final String intermediate;
  final String advanced;

  // ── Workout ──────────────────────────────────────────────────────────────
  final String getReady;
  final String set;
  final String positionCamera;
  final String poseDetected;
  final String cameraPreview;
  final String paused;
  final String setComplete;
  final String correctRep;
  final String watchForm;

  // ── Result ───────────────────────────────────────────────────────────────
  final String workoutComplete;
  final String excellent;
  final String greatJob;
  final String keepGoing;
  final String roomToImprove;
  final String postureScore;
  final String correct;
  final String accuracy;
  final String time;
  final String workoutReplay;
  final String reviewForm;
  final String hide;
  final String view;
  final String loadingReplay;
  final String trainerFeedback;
  final String startNewWorkout;
  final String backToHome;
  final String againBtn;

  // ── Report ───────────────────────────────────────────────────────────────
  final String report;
  final String daily;
  final String weekly;
  final String monthly;
  final String postureScoreChart;
  final String postureScoreSubtitle;
  final String repVolume;
  final String repVolumeSubtitle;
  final String activeTimeChart;
  final String activeTimeSubtitle;
  final String workoutHistory;
  final String reps;
  final String minutes;

  // ── Profile ──────────────────────────────────────────────────────────────
  final String profile;
  final String age;
  final String weight;
  final String height;
  final String totalWorkouts;
  final String settings;
  final String pushNotifications;
  final String darkMode;
  final String soundEffects;
  final String hapticFeedback;
  final String language;
  final String recentActivity;
  final String signOut;
  final String signOutConfirmTitle;
  final String signOutConfirmMsg;
  final String since;
  final String editProfile;
  final String save;
  final String name;
  final String birthDate;
  final String selectBirthDate;

  const AppStrings({
    required this.locale,
    required this.appName,
    required this.appTagline,
    required this.cancel,
    required this.confirm,
    required this.today,
    required this.yesterday,
    required this.daysAgo,
    required this.seeAll,
    required this.again,
    required this.back,
    required this.navHome,
    required this.navCalendar,
    required this.navWorkout,
    required this.navReport,
    required this.navProfile,
    required this.calendar,
    required this.calendarComingSoon,
    required this.welcomeBack,
    required this.createAccount,
    required this.signIn,
    required this.signUp,
    required this.email,
    required this.password,
    required this.fullName,
    required this.alreadyHaveAccount,
    required this.noAccount,
    required this.poweredBy,
    required this.minEightChars,
    required this.nameRequired,
    required this.validEmail,
    required this.signInSubtitle,
    required this.signUpSubtitle,
    required this.username,
    required this.confirmPassword,
    required this.checkDuplicate,
    required this.duplicateAvailable,
    required this.duplicateTaken,
    required this.duplicateCheckRequired,
    required this.gender,
    required this.male,
    required this.female,
    required this.heightCm,
    required this.weightKg,
    required this.workoutGoal,
    required this.goalDiet,
    required this.goalStrength,
    required this.goalPosture,
    required this.passwordMismatch,
    required this.idRequired,
    required this.accountInfo,
    required this.personalInfo,
    required this.bodyStats,
    required this.required,
    required this.greetingMorning,
    required this.greetingAfternoon,
    required this.greetingEvening,
    required this.todaySummary,
    required this.workouts,
    required this.totalReps,
    required this.activeTime,
    required this.avgScore,
    required this.readyToTrain,
    required this.aiRealtime,
    required this.streak,
    required this.recentWorkouts,
    required this.exercises,
    required this.keepChain,
    required this.dayStreak,
    required this.myGoal,
    required this.selectExercise,
    required this.chooseExercise,
    required this.aiTrackForm,
    required this.configureWorkout,
    required this.repsPerSet,
    required this.durationSeconds,
    required this.sets,
    required this.start,
    required this.beginner,
    required this.intermediate,
    required this.advanced,
    required this.getReady,
    required this.set,
    required this.positionCamera,
    required this.poseDetected,
    required this.cameraPreview,
    required this.paused,
    required this.setComplete,
    required this.correctRep,
    required this.watchForm,
    required this.workoutComplete,
    required this.excellent,
    required this.greatJob,
    required this.keepGoing,
    required this.roomToImprove,
    required this.postureScore,
    required this.correct,
    required this.accuracy,
    required this.time,
    required this.workoutReplay,
    required this.reviewForm,
    required this.hide,
    required this.view,
    required this.loadingReplay,
    required this.trainerFeedback,
    required this.startNewWorkout,
    required this.backToHome,
    required this.againBtn,
    required this.report,
    required this.daily,
    required this.weekly,
    required this.monthly,
    required this.postureScoreChart,
    required this.postureScoreSubtitle,
    required this.repVolume,
    required this.repVolumeSubtitle,
    required this.activeTimeChart,
    required this.activeTimeSubtitle,
    required this.workoutHistory,
    required this.reps,
    required this.minutes,
    required this.profile,
    required this.age,
    required this.weight,
    required this.height,
    required this.totalWorkouts,
    required this.settings,
    required this.pushNotifications,
    required this.darkMode,
    required this.soundEffects,
    required this.hapticFeedback,
    required this.language,
    required this.recentActivity,
    required this.signOut,
    required this.signOutConfirmTitle,
    required this.signOutConfirmMsg,
    required this.since,
    required this.editProfile,
    required this.save,
    required this.name,
    required this.birthDate,
    required this.selectBirthDate,
  });

  // ── English ───────────────────────────────────────────────────────────────
  static const en = AppStrings(
    locale: 'en',
    appName: 'BPT',
    appTagline: 'AI-Powered Fitness Coach',
    cancel: 'Cancel',
    confirm: 'Confirm',
    today: 'Today',
    yesterday: 'Yesterday',
    daysAgo: 'd ago',
    seeAll: 'See All',
    again: 'Again',
    back: 'Back',
    navHome: 'Home',
    navCalendar: 'Calendar',
    navWorkout: 'Workout',
    navReport: 'Report',
    navProfile: 'Profile',
    calendar: 'Calendar',
    calendarComingSoon: 'Coming soon',
    welcomeBack: "Let's Get Moving!",
    createAccount: 'Create Account',
    signIn: 'Sign In',
    signUp: 'Sign Up',
    email: 'Email',
    password: 'Password',
    fullName: 'Full Name',
    alreadyHaveAccount: 'Already have an account? ',
    noAccount: "Don't have an account? ",
    poweredBy: 'Powered by AI Pose Estimation',
    minEightChars: 'Min 8 characters',
    nameRequired: 'Name is required',
    validEmail: 'Enter valid email',
    signInSubtitle: 'Your best workout is waiting!',
    signUpSubtitle: 'Start your AI-powered fitness journey',
    username: 'Username',
    confirmPassword: 'Confirm Password',
    checkDuplicate: 'Check',
    duplicateAvailable: 'Username available',
    duplicateTaken: 'Username already taken',
    duplicateCheckRequired: 'Please check username availability',
    gender: 'Gender (optional)',
    male: 'Male',
    female: 'Female',
    heightCm: 'Height (cm)',
    weightKg: 'Weight (kg)',
    workoutGoal: 'Workout Goal',
    goalDiet: 'Diet',
    goalStrength: 'Strength',
    goalPosture: 'Posture Correction',
    passwordMismatch: 'Passwords do not match',
    idRequired: 'Username is required',
    accountInfo: 'Account',
    personalInfo: 'Personal Info',
    bodyStats: 'Body Stats',
    required: 'Required',
    greetingMorning: "Let's crush it today!",
    greetingAfternoon: 'Perfect time to work out!',
    greetingEvening: 'Give it your all tonight!',
    todaySummary: "Today's Summary",
    workouts: 'Workouts',
    totalReps: 'Total Reps',
    activeTime: 'Active Time',
    avgScore: 'Avg Score',
    readyToTrain: 'Ready to Train?',
    aiRealtime: 'AI will analyze your form in real-time',
    streak: 'Streak',
    recentWorkouts: 'Recent Workouts',
    exercises: 'Exercises',
    keepChain: "Keep it up! Don't break the chain.",
    dayStreak: 'Day Streak',
    myGoal: 'My Goal',
    selectExercise: 'Select Exercise',
    chooseExercise: 'Choose Your Exercise',
    aiTrackForm: 'AI will track your form and count reps',
    configureWorkout: 'Configure Workout',
    repsPerSet: 'Reps per Set',
    durationSeconds: 'Duration (seconds)',
    sets: 'Sets',
    start: 'Start',
    beginner: 'Beginner',
    intermediate: 'Intermediate',
    advanced: 'Advanced',
    getReady: 'Get ready!',
    set: 'Set',
    positionCamera: 'Position yourself in frame',
    poseDetected: 'Pose Detected',
    cameraPreview: 'Camera Preview',
    paused: 'Paused',
    setComplete: 'Set complete! Great job!',
    correctRep: 'Perfect rep!',
    watchForm: 'Watch your form!',
    workoutComplete: 'Workout Complete',
    excellent: 'Excellent!',
    greatJob: 'Great Job!',
    keepGoing: 'Keep Going!',
    roomToImprove: 'Room to Improve',
    postureScore: 'Posture Score',
    correct: 'Correct',
    accuracy: 'Accuracy',
    time: 'Time',
    workoutReplay: 'Workout Replay',
    reviewForm: 'Review your form',
    hide: 'Hide',
    view: 'View',
    loadingReplay: 'Loading video...',
    trainerFeedback: 'Trainer Feedback',
    startNewWorkout: 'Start New Workout',
    backToHome: 'Back to Home',
    againBtn: 'Again',
    report: 'Report',
    daily: 'Daily',
    weekly: 'Weekly',
    monthly: 'Monthly',
    postureScoreChart: 'Posture Score',
    postureScoreSubtitle: 'Average score over time',
    repVolume: 'Rep Volume',
    repVolumeSubtitle: 'Total reps completed',
    activeTimeChart: 'Active Time',
    activeTimeSubtitle: 'Minutes worked out',
    workoutHistory: 'Workout History',
    reps: 'reps',
    minutes: 'Minutes',
    profile: 'Profile',
    age: 'Age',
    weight: 'Weight',
    height: 'Height',
    totalWorkouts: 'Total Workouts',
    settings: 'Settings',
    pushNotifications: 'Push Notifications',
    darkMode: 'Dark Mode',
    soundEffects: 'Sound Effects',
    hapticFeedback: 'Haptic Feedback',
    language: 'Language',
    recentActivity: 'Recent Activity',
    signOut: 'Sign Out',
    signOutConfirmTitle: 'Sign Out',
    signOutConfirmMsg: 'Are you sure you want to sign out?',
    since: 'Since',
    editProfile: 'Edit Profile',
    save: 'Save',
    name: 'Name',
    birthDate: 'Date of Birth',
    selectBirthDate: 'Select date of birth',
  );

  // ── Korean ────────────────────────────────────────────────────────────────
  static const ko = AppStrings(
    locale: 'ko',
    appName: 'BPT',
    appTagline: 'AI 피트니스 코치',
    cancel: '취소',
    confirm: '확인',
    today: '오늘',
    yesterday: '어제',
    daysAgo: '일 전',
    seeAll: '전체보기',
    again: '다시',
    back: '뒤로',
    navHome: '홈',
    navCalendar: '캘린더',
    navWorkout: '운동',
    navReport: '리포트',
    navProfile: '내 정보',
    calendar: '캘린더',
    calendarComingSoon: '곧 만나볼 수 있어요',
    welcomeBack: '오늘도 열심히 해봐요!',
    createAccount: '계정 만들기',
    signIn: '로그인',
    signUp: '회원가입',
    email: '이메일',
    password: '비밀번호',
    fullName: '이름',
    alreadyHaveAccount: '이미 계정이 있으신가요? ',
    noAccount: '계정이 없으신가요? ',
    poweredBy: 'AI 자세 추정 기반 서비스',
    minEightChars: '최소 8자 이상',
    nameRequired: '이름을 입력해주세요',
    validEmail: '유효한 이메일을 입력해주세요',
    signInSubtitle: '최고의 운동이 기다리고 있어요!',
    signUpSubtitle: 'AI 피트니스 여정을 시작하세요',
    username: '아이디',
    confirmPassword: '비밀번호 확인',
    checkDuplicate: '중복확인',
    duplicateAvailable: '사용 가능한 아이디입니다',
    duplicateTaken: '이미 사용 중인 아이디입니다',
    duplicateCheckRequired: '아이디 중복확인을 해주세요',
    gender: '성별 (선택)',
    male: '남성',
    female: '여성',
    heightCm: '키 (cm)',
    weightKg: '몸무게 (kg)',
    workoutGoal: '운동 목적',
    goalDiet: '다이어트',
    goalStrength: '근력 향상',
    goalPosture: '자세 교정',
    passwordMismatch: '비밀번호가 일치하지 않습니다',
    idRequired: '아이디를 입력해주세요',
    accountInfo: '계정 정보',
    personalInfo: '개인 정보',
    bodyStats: '신체 정보',
    required: '필수 입력',
    greetingMorning: '오늘도 힘차게 시작해볼까요!',
    greetingAfternoon: '지금이 딱 운동하기 좋은 시간이에요!',
    greetingEvening: '오늘도 최선을 다해봐요!',
    todaySummary: '오늘의 요약',
    workouts: '운동 횟수',
    totalReps: '총 반복',
    activeTime: '활동 시간',
    avgScore: '평균 점수',
    readyToTrain: '운동 시작할까요?',
    aiRealtime: 'AI가 실시간으로 자세를 분석합니다',
    streak: '연속 기록',
    recentWorkouts: '최근 운동',
    exercises: '운동 종목',
    keepChain: '잘 하고 있어요! 연속 기록을 유지하세요.',
    dayStreak: '일 연속',
    myGoal: '나의 목표',
    selectExercise: '운동 선택',
    chooseExercise: '운동을 선택하세요',
    aiTrackForm: 'AI가 자세를 추적하고 횟수를 카운트합니다',
    configureWorkout: '운동 설정',
    repsPerSet: '세트당 반복 수',
    durationSeconds: '지속 시간 (초)',
    sets: '세트 수',
    start: '시작',
    beginner: '초급',
    intermediate: '중급',
    advanced: '고급',
    getReady: '준비하세요!',
    set: '세트',
    positionCamera: '카메라 앞에 서주세요',
    poseDetected: '자세 감지됨',
    cameraPreview: '카메라 미리보기',
    paused: '일시정지',
    setComplete: '세트 완료! 잘 하셨어요!',
    correctRep: '완벽한 동작!',
    watchForm: '자세를 확인하세요!',
    workoutComplete: '운동 완료',
    excellent: '훌륭해요!',
    greatJob: '잘 하셨어요!',
    keepGoing: '계속 노력하세요!',
    roomToImprove: '개선의 여지가 있어요',
    postureScore: '자세 점수',
    correct: '정확',
    accuracy: '정확도',
    time: '시간',
    workoutReplay: '운동 다시보기',
    reviewForm: '자세를 다시 확인해보세요',
    hide: '숨기기',
    view: '보기',
    loadingReplay: '영상 불러오는 중...',
    trainerFeedback: '트레이너 피드백',
    startNewWorkout: '새 운동 시작',
    backToHome: '홈으로',
    againBtn: '다시',
    report: '리포트',
    daily: '일별',
    weekly: '주별',
    monthly: '월별',
    postureScoreChart: '자세 점수',
    postureScoreSubtitle: '시간별 평균 점수',
    repVolume: '반복 볼륨',
    repVolumeSubtitle: '총 완료 반복 수',
    activeTimeChart: '활동 시간',
    activeTimeSubtitle: '운동한 분 수',
    workoutHistory: '운동 기록',
    reps: '회',
    minutes: '분',
    profile: '내 정보',
    age: '나이',
    weight: '체중',
    height: '키',
    totalWorkouts: '총 운동 횟수',
    settings: '설정',
    pushNotifications: '푸시 알림',
    darkMode: '다크 모드',
    soundEffects: '효과음',
    hapticFeedback: '진동 피드백',
    language: '언어',
    recentActivity: '최근 활동',
    signOut: '로그아웃',
    signOutConfirmTitle: '로그아웃',
    signOutConfirmMsg: '정말 로그아웃 하시겠어요?',
    since: '가입년도',
    editProfile: '프로필 편집',
    save: '저장',
    name: '이름',
    birthDate: '생년월일',
    selectBirthDate: '생년월일을 선택하세요',
  );
}
