import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'main.dart';
import 'models.dart';
import 'repository.dart';
import 'screens_documents.dart';
import 'services/planner.dart';
import 'services/reminders.dart';
import 'services/drive_backup.dart';

void notifyUser(BuildContext context,String text) {
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));
}

class HomeShell extends StatefulWidget {
  final StudyRepository store;
  final ThemeSettings theme;
  final String email;
  const HomeShell({super.key,required this.store,required this.theme,required this.email});
  @override State<HomeShell> createState()=>_HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int page=0;
  Timer? retryTimer;
  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    retryTimer=Timer.periodic(const Duration(minutes:2),(_) {
      if(widget.store.pendingCount>0&&!widget.store.syncing)unawaited(widget.store.sync());
    });
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if(state==AppLifecycleState.resumed) unawaited(widget.store.sync());
  }
  @override void dispose(){retryTimer?.cancel();WidgetsBinding.instance.removeObserver(this);super.dispose();}
  @override Widget build(BuildContext context) {
    return AnimatedBuilder(animation:widget.store,builder:(context,_) {
      final store=widget.store;
      return Scaffold(
        appBar:AppBar(title:Row(mainAxisSize:MainAxisSize.min,children:[
          Icon(Icons.auto_stories_rounded,color:Theme.of(context).colorScheme.primary),
          const SizedBox(width:8),const Text('StudyPulse',style:TextStyle(fontWeight:FontWeight.w800)),
        ]),actions:[
          IconButton(tooltip:'Enable reminders',icon:const Icon(Icons.notifications_active_outlined),onPressed:()async {
            final enabled=await ReminderService.instance.requestPermission();
            if(enabled) await ReminderService.instance.refresh(store.all);
            if(context.mounted)notifyUser(context,enabled?'Reminders activated for assignments, quizzes and exams.':'Enable StudyPulse notifications in Android Settings.');
          }),
          IconButton(tooltip:'Sync now',icon:Icon(store.syncing?Icons.sync:Icons.cloud_sync_outlined),onPressed:store.syncing?null:()=>store.sync()),
        ]),
        body:Column(children:[
          Container(color:store.syncError==null?Theme.of(context).colorScheme.primaryContainer:Theme.of(context).colorScheme.errorContainer,
            padding:const EdgeInsets.symmetric(horizontal:16,vertical:7),child:Row(children:[
            Icon(store.syncError==null?Icons.cloud_done_outlined:Icons.cloud_off,size:17),const SizedBox(width:8),
            Expanded(child:Text(store.syncing?'Syncing ${store.pendingCount} changes...':store.syncError!=null?'${store.pendingCount} local changes · cloud unavailable':
              store.pendingCount==0?'Cloud sync completed':'${store.pendingCount} changes saved locally',style:const TextStyle(fontSize:12))),
            if(store.syncError!=null)TextButton(onPressed:()=>notifyUser(context,store.syncError!),child:const Text('Details')),
          ])),
          Expanded(child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:900),child:IndexedStack(index:page,children:[
            DashboardScreen(store:store,email:widget.email),
            LibraryScreen(store:store),
            TasksScreen(store:store),
            FocusScreen(store:store),
            MoreScreen(store:store,settings:widget.theme),
          ])))),
        ]),
        bottomNavigationBar:NavigationBar(selectedIndex:page,onDestinationSelected:(i)=>setState(()=>page=i),destinations:const [
          NavigationDestination(icon:Icon(Icons.space_dashboard_outlined),selectedIcon:Icon(Icons.space_dashboard),label:'Home'),
          NavigationDestination(icon:Icon(Icons.menu_book_outlined),selectedIcon:Icon(Icons.menu_book),label:'Books'),
          NavigationDestination(icon:Icon(Icons.fact_check_outlined),selectedIcon:Icon(Icons.fact_check),label:'Tasks'),
          NavigationDestination(icon:Icon(Icons.timer_outlined),selectedIcon:Icon(Icons.timer),label:'Focus'),
          NavigationDestination(icon:Icon(Icons.tune_outlined),selectedIcon:Icon(Icons.tune),label:'More'),
        ]),
      );
    });
  }
}

class StudentAvatar extends StatefulWidget {
  final String? path;
  final double radius;
  const StudentAvatar({super.key,this.path,this.radius=28});
  @override State<StudentAvatar> createState()=>_StudentAvatarState();
}
class _StudentAvatarState extends State<StudentAvatar> {
  Future<Uint8List>? picture;
  @override void initState(){super.initState();_update();}
  @override void didUpdateWidget(StudentAvatar oldWidget){super.didUpdateWidget(oldWidget);if(oldWidget.path!=widget.path)_update();}
  void _update(){
    final path=widget.path;
    picture=path==null||path.isEmpty?null:Supabase.instance.client.storage.from('sp2_materials').download(path);
  }
  @override Widget build(BuildContext context) {
    return ClipOval(child:SizedBox(width:widget.radius*2,height:widget.radius*2,child:picture==null?
      ColoredBox(color:Theme.of(context).colorScheme.primaryContainer,child:Icon(Icons.person,size:widget.radius,color:Theme.of(context).colorScheme.primary)):
      FutureBuilder<Uint8List>(future:picture,builder:(context,snapshot)=>snapshot.hasData?
        Image.memory(snapshot.data!,fit:BoxFit.cover):
        ColoredBox(color:Theme.of(context).colorScheme.primaryContainer,child:Icon(Icons.person,size:widget.radius)),
      ),
    ));
  }
}

class DashboardScreen extends StatelessWidget {
  final StudyRepository store;
  final String email;
  const DashboardScreen({super.key,required this.store,required this.email});

  @override Widget build(BuildContext context) {
    final scheme=Theme.of(context).colorScheme;
    final profile=store.profile;
    final studentName=profile?.data['name']?.toString().trim();
    final name=studentName!=null&&studentName.isNotEmpty?studentName:email.split('@').first;
    final roll=profile?.data['rollNo']?.toString() ?? '';
    final sessionTime=store.ofKind('session').where((e)=>e.due==studyDay(DateTime.now())).fold<int>(0,(sum,e)=>sum+e.minutes);
    final unfinished=store.all.where((e)=>{'task','assignment','quiz','exam','plan'}.contains(e.kind)&&!e.done).toList()..sort((a,b)=>a.due.compareTo(b.due));
    final trackable=store.all.where((e)=>{'task','assignment','plan','topic'}.contains(e.kind)).toList();
    final completed=trackable.where((e)=>e.done).length;
    return ListView(padding:const EdgeInsets.all(17),children:[
      const SizedBox(height:5),
      Text('YOUR STUDY SPACE',style:TextStyle(letterSpacing:1.4,fontSize:11,fontWeight:FontWeight.w800,color:scheme.primary)),
      const SizedBox(height:8),
      Row(children:[
        StudentAvatar(path:profile?.data['avatarPath']?.toString(),radius:30),const SizedBox(width:12),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Hello, $name 👋',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:24,fontWeight:FontWeight.w800)),
          Text(roll.isEmpty?'Add your student details': 'Roll No: $roll',style:TextStyle(fontSize:12,color:scheme.onSurfaceVariant)),
        ])),
        IconButton.filledTonal(tooltip:'Edit profile',onPressed:()=>editStudentProfile(context,store),icon:const Icon(Icons.edit_outlined)),
      ]),
      const SizedBox(height:18),
      Container(padding:const EdgeInsets.all(21),decoration:BoxDecoration(
        gradient:LinearGradient(colors:[scheme.primary,scheme.tertiary],begin:Alignment.topLeft,end:Alignment.bottomRight),
        borderRadius:BorderRadius.circular(24),
      ),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Row(children:[Icon(Icons.bolt_outlined,color:Colors.white),SizedBox(width:6),Text('TODAY\'S FOCUS',style:TextStyle(color:Colors.white70,letterSpacing:1.1,fontWeight:FontWeight.bold))]),
        const SizedBox(height:16),Text('${sessionTime} / 120 minutes',style:const TextStyle(fontSize:26,color:Colors.white,fontWeight:FontWeight.w900)),
        const SizedBox(height:13),LinearProgressIndicator(value:(sessionTime/120).clamp(0.0,1.0),backgroundColor:Colors.white30,color:Colors.white,minHeight:9,borderRadius:BorderRadius.circular(10)),
        const SizedBox(height:12),const Text('Small study sessions create big results.',style:TextStyle(color:Colors.white70)),
      ])),
      const SizedBox(height:15),
      Row(children:[Expanded(child:_StatCard(icon:Icons.auto_stories_outlined,title:'Books',count:'${store.ofKind('book').length}',color:scheme.primary)),
        const SizedBox(width:10),Expanded(child:_StatCard(icon:Icons.task_alt_outlined,title:'Completed',count:'$completed/${trackable.length}',color:scheme.tertiary))]),
      const SizedBox(height:20),
      Row(children:[const Expanded(child:Text('Upcoming deadlines',style:TextStyle(fontWeight:FontWeight.w800,fontSize:19))),
        FilledButton.tonalIcon(onPressed:()=>editStudyItem(context,store,'assignment'),icon:const Icon(Icons.add,size:17),label:const Text('Add'))]),
      const SizedBox(height:6),
      if(unfinished.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(18),child:Text('No pending work. Add a task or import a book.'))),
      for(final item in unfinished.take(7)) RecordTile(store:store,record:item),
      const SizedBox(height:16),
      Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('Ready for your next exam?',style:TextStyle(fontWeight:FontWeight.bold,fontSize:17)),
        const SizedBox(height:7),const Text('Open a book, import its chapter headings, then generate a dated revision plan.'),
        const SizedBox(height:12),OutlinedButton.icon(icon:const Icon(Icons.auto_awesome_outlined),onPressed:()=>showPlanForBook(context,store),label:const Text('Build my exam plan')),
      ]))),
    ]);
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;final String title;final String count;final Color color;
  const _StatCard({required this.icon,required this.title,required this.count,required this.color});
  @override Widget build(BuildContext context)=>Card(child:Padding(padding:const EdgeInsets.all(17),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Icon(icon,color:color),const SizedBox(height:10),Text(count,style:const TextStyle(fontSize:23,fontWeight:FontWeight.w800)),
    Text(title,style:TextStyle(fontSize:12,color:Theme.of(context).colorScheme.onSurfaceVariant)),
  ])));
}

class LibraryScreen extends StatelessWidget {
  final StudyRepository store;
  const LibraryScreen({super.key,required this.store});
  @override Widget build(BuildContext context){
    final books=store.ofKind('book');
    return ListView(padding:const EdgeInsets.all(16),children:[
      const Text('My library',style:TextStyle(fontSize:26,fontWeight:FontWeight.w800)),
      const SizedBox(height:6),const Text('Books, chapters, study files and smart exam plans.'),
      const SizedBox(height:18),Wrap(spacing:9,runSpacing:9,children:[
        FilledButton.icon(onPressed:()=>editStudyItem(context,store,'book'),icon:const Icon(Icons.add),label:const Text('Add book')),
        OutlinedButton.icon(onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>StudyFilesScreen(store:store))),icon:const Icon(Icons.upload_file),label:const Text('My documents')),
        OutlinedButton.icon(onPressed:()=>showPlanForBook(context,store),icon:const Icon(Icons.auto_awesome),label:const Text('Exam plan')),
      ]),
      const SizedBox(height:16),
      if(books.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(20),child:Text('No books yet. Add a book to begin.'))),
      for(final book in books)Card(child:ExpansionTile(
        leading:Icon(Icons.auto_stories_rounded,color:Theme.of(context).colorScheme.primary),
        title:Text(book.title,style:const TextStyle(fontWeight:FontWeight.w800)),
        subtitle:Text('${store.ofKind('topic').where((e)=>e.bookId==book.id).length} topics · ${store.ofKind('file').where((e)=>e.bookId==book.id).length} files'),
        children:[
          Padding(padding:const EdgeInsets.symmetric(horizontal:10),child:Wrap(spacing:8,children:[
            TextButton.icon(onPressed:()=>editStudyItem(context,store,'book',existing:book),icon:const Icon(Icons.edit_outlined),label:const Text('Edit')),
            TextButton.icon(onPressed:()=>editStudyItem(context,store,'topic',preBook:book.id),icon:const Icon(Icons.add_circle_outline),label:const Text('Add topic')),
            TextButton.icon(onPressed:()=>showPlanForBook(context,store,preBook:book.id),icon:const Icon(Icons.event_note_outlined),label:const Text('Plan')),
          ])),
          for(final chapter in store.ofKind('chapter').where((e)=>e.bookId==book.id)) RecordTile(store:store,record:chapter),
          for(final topic in store.ofKind('topic').where((e)=>e.bookId==book.id)) RecordTile(store:store,record:topic),
        ],
      )),
    ]);
  }
}

class TasksScreen extends StatefulWidget {
  final StudyRepository store;
  const TasksScreen({super.key,required this.store});
  @override State<TasksScreen> createState()=>_TasksScreenState();
}
class _TasksScreenState extends State<TasksScreen> {
  String type='assignment';
  @override Widget build(BuildContext context) {
    final entries=widget.store.ofKind(type);
    return ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Your activities',style:TextStyle(fontSize:26,fontWeight:FontWeight.w800)),
      const SizedBox(height:7),const Text('Assignments, quizzes, exams, habits and spending.'),
      const SizedBox(height:15),SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
        for(final category in const ['assignment','quiz','exam','task','plan','habit','expense']) Padding(padding:const EdgeInsets.only(right:8),child:ChoiceChip(label:Text(category),selected:type==category,onSelected:(_)=>setState(()=>type=category))),
      ])),
      const SizedBox(height:15),FilledButton.icon(onPressed:()=>editStudyItem(context,widget.store,type),icon:const Icon(Icons.add),label:Text('Add $type')),
      const SizedBox(height:12),if(entries.isEmpty)Card(child:Padding(padding:const EdgeInsets.all(18),child:Text('No $type records saved yet.'))),
      for(final entry in entries)RecordTile(store:widget.store,record:entry),
    ]);
  }
}

class RecordTile extends StatelessWidget {
  final StudyRepository store;
  final StudyEntry record;
  const RecordTile({super.key,required this.store,required this.record});
  @override Widget build(BuildContext context){
    final checkable=!{'book','chapter','expense','session','file','profile'}.contains(record.kind);
    return Card(child:ListTile(
      leading:checkable?Checkbox(value:record.done,onChanged:(v)=>store.update(record,{'done':v??false})):Icon(Icons.bookmark_border_rounded,color:Theme.of(context).colorScheme.primary),
      title:Text(record.title,style:TextStyle(fontWeight:FontWeight.w600,decoration:record.done?TextDecoration.lineThrough:null)),
      subtitle:Text([record.kind,if(record.due.isNotEmpty)record.due].join(' · ')),
      onTap:()=>editStudyItem(context,store,record.kind,existing:record),
      trailing:PopupMenuButton<String>(onSelected:(v){if(v=='delete')store.delete(record);else editStudyItem(context,store,record.kind,existing:record);},itemBuilder:(_)=>const [
        PopupMenuItem(value:'edit',child:Text('Edit')),PopupMenuItem(value:'delete',child:Text('Delete')),
      ]),
    ));
  }
}

Future<void> editStudyItem(BuildContext context,StudyRepository store,String kind,{StudyEntry? existing,String? preBook}) async {
  final title=TextEditingController(text:existing?.title??'');
  final notes=TextEditingController(text:existing?.data['notes']?.toString()??'');
  final amount=TextEditingController(text:existing?.data['amount']?.toString()??'');
  var date=dayFromString(existing?.due??'')??DateTime.now().add(const Duration(days:1));
  String? bookId=preBook??existing?.bookId;
  final books=store.ofKind('book');
  final needsDue={'task','assignment','quiz','exam','plan','habit','expense'}.contains(kind);
  var saving=false;
  String? error;
  try {
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,useSafeArea:true,backgroundColor:Colors.transparent,builder:(sheetContext)=>StatefulBuilder(builder:(sheetContext,refresh)=>
      Padding(padding:EdgeInsets.only(bottom:MediaQuery.viewInsetsOf(sheetContext).bottom),child:Container(
        decoration:BoxDecoration(color:Theme.of(context).colorScheme.surface,borderRadius:const BorderRadius.vertical(top:Radius.circular(28))),
        constraints:BoxConstraints(maxHeight:MediaQuery.sizeOf(sheetContext).height*.85),
        child:SingleChildScrollView(padding:const EdgeInsets.all(22),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Center(child:Container(width:44,height:5,decoration:BoxDecoration(color:Colors.grey.shade300,borderRadius:BorderRadius.circular(10)))),
          const SizedBox(height:20),Text('${existing==null?'Add':'Edit'} ${kind[0].toUpperCase()}${kind.substring(1)}',style:const TextStyle(fontWeight:FontWeight.w800,fontSize:22)),
          const SizedBox(height:18),TextField(controller:title,maxLength:160,decoration:InputDecoration(labelText:kind=='book'?'Book name *':'Title *',prefixIcon:const Icon(Icons.edit_note))),
          const SizedBox(height:8),TextField(controller:notes,maxLines:3,decoration:const InputDecoration(labelText:'Notes / description')),
          if(kind!='book'&&kind!='profile'&&books.isNotEmpty)...[
            const SizedBox(height:12),DropdownButtonFormField<String>(initialValue:books.any((b)=>b.id==bookId)?bookId:null,
              hint:const Text('Choose book (optional)'),decoration:const InputDecoration(labelText:'Related book'),
              items:[for(final book in books)DropdownMenuItem(value:book.id,child:Text(book.title,overflow:TextOverflow.ellipsis))],onChanged:(value)=>refresh(()=>bookId=value)),
          ],
          if(needsDue)...[
            const SizedBox(height:14),OutlinedButton.icon(icon:const Icon(Icons.calendar_month),label:Text('Due date: ${studyDay(date)}'),onPressed:()async {
              final chosen=await showDatePicker(context:sheetContext,initialDate:date,firstDate:DateTime(2020),lastDate:DateTime(2100));
              if(chosen!=null)refresh(()=>date=chosen);
            }),
          ],
          if(kind=='expense')...[
            const SizedBox(height:12),TextField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Amount (PKR)')),
          ],
          if(error!=null)...[const SizedBox(height:10),Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))],
          const SizedBox(height:18),FilledButton.icon(icon:const Icon(Icons.check_circle_outline),label:Text(saving?'Saving...':'Save $kind'),onPressed:saving?null:()async {
            if(title.text.trim().isEmpty){refresh(()=>error='Please enter a title.');return;}
            if((kind=='topic'||kind=='chapter')&&(bookId==null||bookId!.isEmpty)){
              refresh(()=>error='Select a book for this ${kind}.');return;
            }
            refresh((){saving=true;error=null;});
            try{
              final data=<String,dynamic>{
                'title':title.text.trim(),'notes':notes.text.trim(),'done':existing?.done??false,
                if(needsDue)'due':studyDay(date),
                if(bookId!=null&&bookId!.isNotEmpty)'bookId':bookId,
                if(kind=='expense')'amount':double.tryParse(amount.text)??0,
              };
              if(existing==null){await store.add(kind,data);}else{await store.update(existing,data);}
              if(sheetContext.mounted)Navigator.pop(sheetContext);
              if(context.mounted)notifyUser(context,'Saved locally. Cloud sync follows.');
            }catch(e){if(sheetContext.mounted)refresh(()=>error='Save failed: $e');}
            finally{if(sheetContext.mounted)refresh(()=>saving=false);}
          }),
          TextButton(onPressed:saving?null:()=>Navigator.pop(sheetContext),child:const Text('Cancel')),
        ])),
      )),
    ));
  } finally {title.dispose();notes.dispose();amount.dispose();}
}

Future<void> editStudentProfile(BuildContext context,StudyRepository store) async {
  final existing=store.profile;
  final name=TextEditingController(text:existing?.data['name']?.toString()??'');
  final roll=TextEditingController(text:existing?.data['rollNo']?.toString()??'');
  final grade=TextEditingController(text:existing?.data['program']?.toString()??'');
  String? imagePath=existing?.data['avatarPath']?.toString();
  Uint8List? preview;
  var busy=false;
  String? error;
  try {
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,useSafeArea:true,builder:(sheetContext)=>StatefulBuilder(builder:(sheetContext,redraw)=>
      Padding(padding:EdgeInsets.only(bottom:MediaQuery.viewInsetsOf(sheetContext).bottom),child:SingleChildScrollView(padding:const EdgeInsets.all(22),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        const Text('Student profile',style:TextStyle(fontSize:24,fontWeight:FontWeight.w800)),const SizedBox(height:10),
        Center(child:preview!=null?ClipOval(child:Image.memory(preview!,width:92,height:92,fit:BoxFit.cover)):StudentAvatar(path:imagePath,radius:46)),
        TextButton.icon(onPressed:busy?null:()async {
          try{
            final picked=await FilePicker.pickFile(type:FileType.custom,allowedExtensions:['jpg','jpeg','png']);
            if(picked==null)return;
            final bytes=await picked.readAsBytes();
            if(bytes.length>3*1024*1024)throw StateError('Choose a photo below 3 MB');
            redraw((){preview=bytes;error=null;});
          }catch(e){redraw(()=>error='$e');}
        },icon:const Icon(Icons.photo_camera_outlined),label:const Text('Choose student photo')),
        const SizedBox(height:12),TextField(controller:name,decoration:const InputDecoration(labelText:'Full name *')),
        const SizedBox(height:12),TextField(controller:roll,decoration:const InputDecoration(labelText:'Roll number *')),
        const SizedBox(height:12),TextField(controller:grade,decoration:const InputDecoration(labelText:'Program / semester')),
        if(error!=null)...[const SizedBox(height:9),Text(error!,style:const TextStyle(color:Colors.red))],
        const SizedBox(height:20),FilledButton.icon(icon:const Icon(Icons.save_outlined),label:Text(busy?'Saving...':'Save student profile'),onPressed:busy?null:()async {
          if(name.text.trim().isEmpty||roll.text.trim().isEmpty){redraw(()=>error='Name and roll number are required.');return;}
          redraw((){busy=true;error=null;});
          try{
            if(preview!=null){
              final user=Supabase.instance.client.auth.currentUser;
              if(user==null)throw StateError('Sign in before uploading a photo');
              final path='${user.id}/${const Uuid().v4()}.jpg';
              final original=preview!;
              final contentType=original.length>3 && original[0]==0x89 && original[1]==0x50?'image/png':'image/jpeg';
              imagePath=contentType=='image/png'?path.replaceAll('.jpg','.png'):path;
              await Supabase.instance.client.storage.from('sp2_materials').uploadBinary(imagePath!,original,fileOptions:FileOptions(contentType:contentType,upsert:false));
            }
            final data=<String,dynamic>{'title':name.text.trim(),'name':name.text.trim(),'rollNo':roll.text.trim(),'program':grade.text.trim(),'avatarPath':imagePath??''};
            if(existing==null){await store.add('profile',data);}else{await store.update(existing,data);}
            if(sheetContext.mounted)Navigator.pop(sheetContext);
            if(context.mounted)notifyUser(context,'Student profile saved.');
          }catch(e){if(sheetContext.mounted)redraw(()=>error='Profile error: $e');}
          finally{if(sheetContext.mounted)redraw(()=>busy=false);}
        }),
        TextButton(onPressed:()=>Navigator.pop(sheetContext),child:const Text('Cancel')),
      ]))),
    ));
  } finally {name.dispose();roll.dispose();grade.dispose();}
}

Future<void> showPlanForBook(BuildContext context,StudyRepository store,{String? preBook}) async {
  final books=store.ofKind('book');
  if(books.isEmpty){notifyUser(context,'Create a book first.');return;}
  String? selected=preBook??books.first.id;
  DateTime examDate=DateTime.now().add(const Duration(days:10));
  int sessionsPerDay=3;
  int minutes=35;
  final result=await showModalBottomSheet<({String bookId,DateTime examDate,int capacity,int minutes})>(
    context:context,isScrollControlled:true,useSafeArea:true,
    builder:(sheetContext)=>StatefulBuilder(builder:(sheetContext,refresh)=>Padding(
      padding:EdgeInsets.only(bottom:MediaQuery.viewInsetsOf(sheetContext).bottom),
      child:SingleChildScrollView(padding:const EdgeInsets.all(22),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        const Text('Create your exam study plan',style:TextStyle(fontSize:23,fontWeight:FontWeight.w800)),
        const SizedBox(height:9),const Text('Pick a book, exam date and daily study capacity. The plan is created from unfinished topics in that book.'),
        const SizedBox(height:17),DropdownButtonFormField<String>(initialValue:books.any((b)=>b.id==selected)?selected:null,
          decoration:const InputDecoration(labelText:'Select book'),items:[for(final book in books)DropdownMenuItem(value:book.id,child:Text(book.title,overflow:TextOverflow.ellipsis))],
          onChanged:(v)=>refresh(()=>selected=v)),
        const SizedBox(height:12),OutlinedButton.icon(onPressed:()async {
          final chosen=await showDatePicker(context:sheetContext,initialDate:examDate,firstDate:DateTime.now(),lastDate:DateTime(2100));
          if(chosen!=null)refresh(()=>examDate=chosen);
        },icon:const Icon(Icons.calendar_month),label:Text('Exam on ${studyDay(examDate)}')),
        const SizedBox(height:8),Text('Sessions per day: $sessionsPerDay'),Slider(value:sessionsPerDay.toDouble(),min:1,max:8,divisions:7,label:'$sessionsPerDay',onChanged:(v)=>refresh(()=>sessionsPerDay=v.round())),
        Text('Minutes per session: $minutes'),Slider(value:minutes.toDouble(),min:15,max:90,divisions:5,label:'$minutes',onChanged:(v)=>refresh(()=>minutes=v.round())),
        const SizedBox(height:10),FilledButton.icon(onPressed:selected==null?null:()=>Navigator.pop(sheetContext,(bookId:selected!,examDate:examDate,capacity:sessionsPerDay,minutes:minutes)),icon:const Icon(Icons.auto_awesome),label:const Text('Preview schedule')),
        const SizedBox(height:8),TextButton(onPressed:()=>Navigator.pop(sheetContext),child:const Text('Cancel')),
      ])),
    )),
  );
  if(result==null||!context.mounted)return;
  final topics=store.ofKind('topic');
  final currentPlans=store.ofKind('plan');
  PlannerResult planned;
  try{
    planned=ExamPlanner.generate(topics:topics,plans:currentPlans,bookId:result.bookId,examDate:result.examDate,today:DateTime.now(),dailyLimit:result.capacity,minutes:result.minutes);
  }catch(e){notifyUser(context,'Study plan error: $e');return;}
  if(planned.sessions.isEmpty){notifyUser(context,'No new topics found. Import chapters into this book, or mark old plans completed.');return;}
  final accept=await showDialog<bool>(context:context,builder:(dialogContext)=>AlertDialog(
    title:Text('Preview ${planned.sessions.length} study sessions'),
    content:SizedBox(width:430,height:370,child:Column(children:[
      if(planned.overloaded>0)Padding(padding:const EdgeInsets.only(bottom:9),child:Text(
        '${planned.overloaded} session(s) exceed your daily limit. Move the exam date later or increase your capacity.',
        style:TextStyle(color:Theme.of(context).colorScheme.error))),
      Expanded(child:ListView(children:[for(final session in planned.sessions)ListTile(
        leading:Icon(session.overCapacity?Icons.warning_amber:Icons.event_available_outlined),title:Text(session.title),
        subtitle:Text('${session.due} · ${session.minutes} minutes'),
      )])),
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),
      FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('Save schedule'))],
  ));
  if(accept!=true)return;
  try{
    for(final session in planned.sessions){
      await store.add('plan',{'title':'Study: ${session.title}','topicId':session.topicId,'bookId':session.bookId,
        'due':session.due,'examDate':studyDay(result.examDate),'minutes':session.minutes,'done':false,
        'notes':'Generated from book topics for exam preparation'},syncNow:false);
    }
    unawaited(store.sync());
    if(context.mounted)notifyUser(context,'${planned.sessions.length} revision sessions saved. Open Tasks → plan.');
  }catch(e){if(context.mounted)notifyUser(context,'Could not save plan: $e');}
}

class FocusScreen extends StatefulWidget {
  final StudyRepository store;
  const FocusScreen({super.key,required this.store});
  @override State<FocusScreen> createState()=>_FocusScreenState();
}
class _FocusScreenState extends State<FocusScreen> {
  static const total=25*60;
  Timer? timer;
  int seconds=total;
  bool running=false;
  void start(){
    timer?.cancel();setState(()=>running=true);
    timer=Timer.periodic(const Duration(seconds:1),(_){
      if(!mounted)return;
      if(seconds>1){setState(()=>seconds--);}else{unawaited(save());}
    });
  }
  void pause(){timer?.cancel();setState(()=>running=false);}
  Future<void> save() async {
    timer?.cancel();
    final minutes=((total-seconds)/60).ceil();
    setState((){running=false;seconds=total;});
    if(minutes<1){notifyUser(context,'Study for at least one minute first.');return;}
    await widget.store.add('session',{'title':'Focus session','minutes':minutes,'due':studyDay(DateTime.now()),'done':true});
    if(mounted)notifyUser(context,'Saved $minutes minutes of study time.');
  }
  @override void dispose(){timer?.cancel();super.dispose();}
  @override Widget build(BuildContext context){
    final theme=Theme.of(context).colorScheme;
    final time='${(seconds~/60).toString().padLeft(2,'0')}:${(seconds%60).toString().padLeft(2,'0')}';
    return ListView(padding:const EdgeInsets.all(20),children:[
      const Text('Focus mode',style:TextStyle(fontSize:26,fontWeight:FontWeight.w800)),const SizedBox(height:7),const Text('25 minutes of distraction-free studying.'),
      const SizedBox(height:22),Card(child:Padding(padding:const EdgeInsets.all(27),child:Column(children:[
        Icon(Icons.timelapse_rounded,size:58,color:theme.primary),const SizedBox(height:18),
        Text(time,style:const TextStyle(fontSize:64,fontWeight:FontWeight.w900)),
        const SizedBox(height:15),LinearProgressIndicator(value:(total-seconds)/total,minHeight:10,borderRadius:BorderRadius.circular(10)),
        const SizedBox(height:22),Wrap(alignment:WrapAlignment.center,spacing:8,runSpacing:8,children:[
          FilledButton.icon(onPressed:running?pause:start,icon:Icon(running?Icons.pause:Icons.play_arrow),label:Text(running?'Pause':'Start')),
          OutlinedButton.icon(onPressed:()=>setState((){timer?.cancel();running=false;seconds=total;}),icon:const Icon(Icons.restart_alt),label:const Text('Reset')),
          OutlinedButton.icon(onPressed:save,icon:const Icon(Icons.save_outlined),label:const Text('Save time')),
        ]),
      ]))),const SizedBox(height:12),Card(child:Padding(padding:const EdgeInsets.all(17),child:Text('${widget.store.ofKind('session').length} completed focus sessions',textAlign:TextAlign.center))),
    ]);
  }
}

class MoreScreen extends StatefulWidget {
  final StudyRepository store;
  final ThemeSettings settings;
  const MoreScreen({super.key,required this.store,required this.settings});
  @override State<MoreScreen> createState()=>_MoreScreenState();
}
class _MoreScreenState extends State<MoreScreen> {
  bool waiting=false;
  Future<void> backup()async{
    setState(()=>waiting=true);
    try{final filename=await DriveBackupService.instance.createBackup(widget.store);if(mounted)notifyUser(context,'Google Drive backup saved: $filename');}
    catch(e){if(mounted)notifyUser(context,'Google Drive backup failed: $e');}
    finally{if(mounted)setState(()=>waiting=false);}
  }
  Future<void> restore()async{
    final proceed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Restore latest backup?'),
      content:const Text('Restore records and document files belonging to this Supabase account. Newer local records will be preserved.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Restore'))],
    ));
    if(proceed!=true)return;
    setState(()=>waiting=true);
    try{final count=await DriveBackupService.instance.restoreLatest(widget.store);if(mounted)notifyUser(context,'Restored $count study records from Google Drive.');}
    catch(e){if(mounted)notifyUser(context,'Restore failed: $e');}
    finally{if(mounted)setState(()=>waiting=false);}
  }
  @override Widget build(BuildContext context){
    final colors=ThemeSettings.colors;
    final tracked=widget.store.all.where((e)=>{'topic','assignment','task','plan'}.contains(e.kind)).toList();
    final done=tracked.where((e)=>e.done).length;
    final expenses=widget.store.ofKind('expense').fold<double>(0,(sum,e)=>sum+((e.data['amount'] as num?)?.toDouble()??0));
    return ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Your settings',style:TextStyle(fontWeight:FontWeight.w800,fontSize:26)),const SizedBox(height:15),
      Card(child:Padding(padding:const EdgeInsets.all(17),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('Make StudyPulse yours',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:12),
        Wrap(spacing:14,runSpacing:12,children:[for(var i=0;i<colors.length;i++)InkWell(onTap:()=>widget.settings.choose(i),borderRadius:BorderRadius.circular(40),child:CircleAvatar(
          radius:23,backgroundColor:colors[i],child:i==widget.settings.selection?const Icon(Icons.check,color:Colors.white):null,
        ))]),
        const SizedBox(height:10),SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Dark mode'),value:widget.settings.dark,onChanged:widget.settings.setDark),
        OutlinedButton.icon(onPressed:()=>editStudentProfile(context,widget.store),icon:const Icon(Icons.person_outline),label:const Text('Edit name, roll no. and photo')),
      ]))),const SizedBox(height:12),
      Card(child:Padding(padding:const EdgeInsets.all(17),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('Plan & progress',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:9),
        Text('$done / ${tracked.length} learning items completed'),const SizedBox(height:10),LinearProgressIndicator(value:tracked.isEmpty?0:done/tracked.length,minHeight:9),
        const SizedBox(height:10),Text('Expenses recorded: PKR ${expenses.toStringAsFixed(2)}'),
        Text('${widget.store.ofKind('session').length} focus sessions'),
        const SizedBox(height:10),FilledButton.tonalIcon(icon:const Icon(Icons.auto_awesome),onPressed:()=>showPlanForBook(context,widget.store),label:const Text('Generate exam study plan')),
      ]))),const SizedBox(height:12),
      Card(child:Padding(padding:const EdgeInsets.all(17),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('Google Drive full backup',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:8),
        const Text('Back up study records and downloaded documents (up to 25 MB total). Requires Google OAuth setup and internet.'),
        const SizedBox(height:14),Wrap(spacing:9,runSpacing:8,children:[
          FilledButton.icon(onPressed:waiting?null:backup,icon:const Icon(Icons.cloud_upload_outlined),label:const Text('Back up')),
          OutlinedButton.icon(onPressed:waiting?null:restore,icon:const Icon(Icons.restore),label:const Text('Restore')),
        ]),
        if(waiting)...[const SizedBox(height:9),const LinearProgressIndicator()],
      ]))),const SizedBox(height:12),
      Card(child:Padding(padding:const EdgeInsets.all(17),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('Cloud sync',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:8),
        Text('Local changes pending: ${widget.store.pendingCount}'),
        if(widget.store.lastSynced!=null)Text('Last synced: ${widget.store.lastSynced}'),
        if(widget.store.syncError!=null)SelectableText(widget.store.syncError!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
        const SizedBox(height:10),OutlinedButton.icon(icon:const Icon(Icons.sync),onPressed:widget.store.syncing?null:widget.store.sync,label:const Text('Sync now')),
      ]))),const SizedBox(height:14),
      FilledButton.tonalIcon(onPressed:()=>Supabase.instance.client.auth.signOut(),icon:const Icon(Icons.logout),label:const Text('Sign out')),
    ]);
  }
}
