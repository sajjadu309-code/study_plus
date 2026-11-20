import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'repository.dart';
import 'services/reminders.dart';
import 'screens.dart';

const supabaseUrl=String.fromEnvironment('SUPABASE_URL',defaultValue:'https://jljkjtxcdfqcgtamkvjl.supabase.co');
const supabasePublishableKey=String.fromEnvironment('SUPABASE_ANON_KEY',defaultValue:'sb_publishable_Lc2t8ZbV-x850ANPEMC79A_dtLsOTDW');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url:supabaseUrl,publishableKey:supabasePublishableKey);
  try { await ReminderService.instance.initialize(); } catch (e) { debugPrint('Notifications unavailable: $e'); }
  runApp(const StudyPulseApp());
}

class ThemeSettings extends ChangeNotifier {
  final _prefs=SharedPreferencesAsync();
  static const colors=[Color(0xFF6548E8),Color(0xFF087E8B),Color(0xFFEA6482),Color(0xFF2E9469),Color(0xFFEC8642)];
  int selection=0;
  bool dark=false;
  Future<void> load() async {
    selection=((await _prefs.getInt('sp_theme_index')) ?? 0).clamp(0, colors.length-1).toInt();
    dark=(await _prefs.getBool('sp_theme_dark')) ?? false;
    notifyListeners();
  }
  Future<void> choose(int index) async {
    selection=index.clamp(0,colors.length-1);
    await _prefs.setInt('sp_theme_index',selection);
    notifyListeners();
  }
  Future<void> setDark(bool value) async {
    dark=value; await _prefs.setBool('sp_theme_dark',value); notifyListeners();
  }
  Color get color=>colors[selection];
}

class StudyPulseApp extends StatefulWidget {
  const StudyPulseApp({super.key});
  @override State<StudyPulseApp> createState()=>_StudyPulseAppState();
}

class _StudyPulseAppState extends State<StudyPulseApp> {
  final store=StudyRepository();
  final theme=ThemeSettings();
  StreamSubscription<AuthState>? authSubscription;
  User? user;

  @override void initState() {
    super.initState();
    unawaited(theme.load());
    user=Supabase.instance.client.auth.currentUser;
    if (user!=null) unawaited(store.open(user!));
    authSubscription=Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      final next=state.session?.user;
      if (next?.id==user?.id || !mounted) return;
      setState(()=>user=next);
      if (next==null) { store.closeAccount(); } else { unawaited(store.open(next)); }
    });
  }

  @override void dispose() {
    authSubscription?.cancel(); store.dispose(); theme.dispose(); super.dispose();
  }

  @override Widget build(BuildContext context) {
    return AnimatedBuilder(animation:theme,builder:(context,_) {
      final light=ThemeData(
        useMaterial3:true,
        colorScheme:ColorScheme.fromSeed(seedColor:theme.color,brightness:Brightness.light),
        scaffoldBackgroundColor:const Color(0xFFF7F7FB),
        appBarTheme:const AppBarTheme(backgroundColor:Color(0xFFF7F7FB),scrolledUnderElevation:0),
        cardTheme:CardThemeData(color:Colors.white,elevation:0,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(22))),
        inputDecorationTheme:InputDecorationTheme(
          filled:true,fillColor:Colors.white,contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:14),
          border:OutlineInputBorder(borderRadius:BorderRadius.circular(15),borderSide:BorderSide(color:Colors.grey.shade300)),
          enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(15),borderSide:BorderSide(color:Colors.grey.shade300)),
        ),
        filledButtonTheme:FilledButtonThemeData(style:FilledButton.styleFrom(
          padding:const EdgeInsets.symmetric(horizontal:20,vertical:15),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)),
        )),
      );
      return MaterialApp(
        debugShowCheckedModeBanner:false,
        title:'StudyPulse',theme:light,
        darkTheme:ThemeData(useMaterial3:true,colorScheme:ColorScheme.fromSeed(seedColor:theme.color,brightness:Brightness.dark)),
        themeMode:theme.dark?ThemeMode.dark:ThemeMode.light,
        home:user==null ? const LoginScreen() : HomeShell(store:store,theme:theme,email:user!.email??'Student'),
      );
    });
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState()=>_LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email=TextEditingController();
  final password=TextEditingController();
  bool register=false, busy=false;
  String? error;
  @override void dispose(){email.dispose();password.dispose();super.dispose();}

  Future<void> submit() async {
    if (email.text.trim().isEmpty || password.text.length<6) {
      setState(()=>error='Enter email and a password of at least 6 characters');return;
    }
    setState((){busy=true;error=null;});
    try {
      final auth=Supabase.instance.client.auth;
      if (register) {
        final response=await auth.signUp(email:email.text.trim(),password:password.text);
        if (mounted && response.session==null) {
          setState(()=>error='Account created. Confirm your email, then sign in.');
        }
      } else {
        await auth.signInWithPassword(email:email.text.trim(),password:password.text);
      }
    } catch(e) {if(mounted)setState(()=>error=e.toString());}
    finally {if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context) {
    final color=Theme.of(context).colorScheme.primary;
    return Scaffold(body:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(20),child:ConstrainedBox(
      constraints:const BoxConstraints(maxWidth:440),child:Card(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[
        Container(width:66,height:66,decoration:BoxDecoration(color:color.withValues(alpha:.12),borderRadius:BorderRadius.circular(20)),child:Icon(Icons.auto_stories_rounded,size:36,color:color)),
        const SizedBox(height:16),const Text('StudyPulse',style:TextStyle(fontSize:30,fontWeight:FontWeight.w800)),
        const SizedBox(height:7),const Text('Your smarter study space',style:TextStyle(color:Colors.grey)),
        const SizedBox(height:28),TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'Email',prefixIcon:Icon(Icons.mail_outline))),
        const SizedBox(height:14),TextField(controller:password,obscureText:true,decoration:const InputDecoration(labelText:'Password',prefixIcon:Icon(Icons.lock_outline))),
        if(error!=null)...[const SizedBox(height:12),Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))],
        const SizedBox(height:22),SizedBox(width:double.infinity,child:FilledButton(onPressed:busy?null:submit,child:Text(busy?'Please wait...':register?'Create account':'Sign in'))),
        TextButton(onPressed:busy?null:()=>setState(()=>register=!register),child:Text(register?'Already have an account? Sign in':'New here? Create an account')),
      ])))))));
  }
}
