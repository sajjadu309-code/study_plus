import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'repository.dart';
import 'services/documents.dart';

class StudyFilesScreen extends StatefulWidget {
  final StudyRepository store;
  const StudyFilesScreen({super.key,required this.store});
  @override State<StudyFilesScreen> createState()=>_StudyFilesScreenState();
}

class _StudyFilesScreenState extends State<StudyFilesScreen> {
  bool busy=false;
  String? error;
  String? selectedBookId;
  static const maxBytes=15*1024*1024;
  static const allowed=['pdf','docx','pptx','txt','md','jpg','jpeg','png'];

  String contentType(String extension) {
    switch(extension){
      case 'pdf':return 'application/pdf';
      case 'docx':return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'pptx':return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'jpg':case 'jpeg':return 'image/jpeg';
      case 'png':return 'image/png';
      case 'md':return 'text/markdown';
      default:return 'text/plain';
    }
  }

  Future<void> upload() async {
    if(busy)return;
    setState((){busy=true;error=null;});
    try{
      final picked=await FilePicker.pickFile(type:FileType.custom,allowedExtensions:allowed);
      if(picked==null)return;
      final name=picked.name;
      final ext=name.split('.').last.toLowerCase();
      final size=picked.lengthSync()??await picked.length();
      if(size!=null && size>maxBytes)throw StateError('File exceeds the 15 MB upload limit.');
      final bytes=await picked.readAsBytes();
      if(bytes.isEmpty||bytes.length>maxBytes)throw StateError('File empty or larger than 15 MB.');
      final user=Supabase.instance.client.auth.currentUser;
      if(user==null)throw StateError('Sign in before uploading files.');
      final path='${user.id}/${const Uuid().v4()}.$ext';
      await Supabase.instance.client.storage.from('sp2_materials').uploadBinary(path,bytes,
        fileOptions:FileOptions(contentType:contentType(ext),upsert:false));
      await widget.store.add('file',{'title':name,'name':name,'extension':ext,'storagePath':path,
        'bookId':selectedBookId??'','sizeBytes':bytes.length,'notes':'Uploaded study material'});
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$name uploaded successfully.')));
      if(selectedBookId!=null && {'pdf','docx','pptx','txt','md'}.contains(ext)){
        try{
          final text=await DocumentText.extract(bytes,ext);
          if(mounted)await reviewTopics(text,selectedBookId!,name,path);
        }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Uploaded, but topic extraction needs review: $e')));}
      }
    } on StorageException catch(e) {
      if(mounted)setState(()=>error=e.statusCode=='404'?
        'Supabase bucket sp2_materials was not found. Run supabase/SETUP.sql in the same Supabase project and try again.':
        'Supabase Storage error ${e.statusCode}: ${e.message}');
    }catch(e){if(mounted)setState(()=>error='Upload failed: $e');}
    finally{if(mounted)setState(()=>busy=false);}
  }

  Future<void> reviewTopics(String text,String book,String fileName,String storagePath)async{
    final headings=DocumentText.topics(text);
    if(headings.isEmpty){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('File saved. No reliable headings found; add topics manually or use a structured PDF.')));return;}
    final selected=headings.toSet();
    final confirm=await showDialog<bool>(context:context,builder:(dialogContext)=>StatefulBuilder(builder:(dialogContext,redraw)=>AlertDialog(
      title:Text('${headings.length} suggested topics'),
      content:SizedBox(width:420,height:370,child:Column(children:[
        const Text('Choose the chapter headings to add to the selected book.'),
        const SizedBox(height:12),Expanded(child:ListView(children:[for(final topic in headings)CheckboxListTile(
          dense:true,title:Text(topic),value:selected.contains(topic),onChanged:(checked)=>redraw((){
            if(checked==true){selected.add(topic);}else{selected.remove(topic);}
          }),
        )])),
      ])),actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Skip')),
        FilledButton(onPressed:selected.isEmpty?null:()=>Navigator.pop(dialogContext,true),child:const Text('Add topics'))],
    )));
    if(confirm!=true)return;
    final existing=widget.store.ofKind('topic').where((e)=>e.bookId==book).map((e)=>e.title.toLowerCase()).toSet();
    var added=0;
    for(final topic in headings){
      if(!selected.contains(topic)||!existing.add(topic.toLowerCase()))continue;
      await widget.store.add('topic',{'title':topic,'bookId':book,'sourcePath':storagePath,'sourceName':fileName,'done':false,'notes':'Imported from document'},syncNow:false);
      added++;
    }
    unawaited(widget.store.sync());
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$added topics added to your book. Open Exam plan to schedule them.')));
  }

  Future<void> deleteFile(StudyEntry file) async {
    try{
      final path=file.data['storagePath']?.toString()??'';
      if(path.isNotEmpty)await Supabase.instance.client.storage.from('sp2_materials').remove([path]);
      await widget.store.delete(file);
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Document deleted.')));
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not delete: $e')));}
  }

  @override Widget build(BuildContext context){
    final books=widget.store.ofKind('book');
    return Scaffold(appBar:AppBar(title:const Text('My study documents')),body:AnimatedBuilder(animation:widget.store,builder:(context,_){
      final files=widget.store.ofKind('file');
      return ListView(padding:const EdgeInsets.all(16),children:[
        Card(child:Padding(padding:const EdgeInsets.all(19),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Icon(Icons.cloud_upload_outlined,color:Theme.of(context).colorScheme.primary,size:44),const SizedBox(height:10),
          const Text('Upload and learn',textAlign:TextAlign.center,style:TextStyle(fontSize:22,fontWeight:FontWeight.w800)),
          const SizedBox(height:9),const Text('PDF, DOCX, PPTX, TXT, Markdown and images · maximum 15 MB.',textAlign:TextAlign.center),
          const SizedBox(height:16),DropdownButtonFormField<String>(
            initialValue:books.any((e)=>e.id==selectedBookId)?selectedBookId:null,
            hint:const Text('Choose book for topic extraction'),
            items:[for(final book in books)DropdownMenuItem(value:book.id,child:Text(book.title,overflow:TextOverflow.ellipsis))],
            onChanged:(v)=>setState(()=>selectedBookId=v),
          ),const SizedBox(height:14),
          FilledButton.icon(onPressed:busy?null:upload,icon:const Icon(Icons.upload_file_outlined),label:Text(busy?'Uploading...':'Choose and upload file')),
          if(busy)...[const SizedBox(height:12),const LinearProgressIndicator()],
          if(error!=null)...[const SizedBox(height:12),SelectableText(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))],
          const SizedBox(height:9),const Text('After upload, review detected chapter headings and add them to the book.',style:TextStyle(fontSize:12,color:Colors.grey)),
        ]))),const SizedBox(height:18),const Text('Uploaded material',style:TextStyle(fontWeight:FontWeight.w800,fontSize:20)),const SizedBox(height:8),
        if(files.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(20),child:Text('No uploaded documents.'))),
        for(final file in files)Card(child:ListTile(
          leading:Icon(Icons.description_outlined,color:Theme.of(context).colorScheme.primary),title:Text(file.title),
          subtitle:Text('${file.data['extension']?.toString().toUpperCase()??''} · ${((file.data['sizeBytes'] as num? ?? 0)/1024).round()} KB'),
          onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>StudyDocumentReader(entry:file))),
          trailing:PopupMenuButton<String>(onSelected:(v){if(v=='delete')deleteFile(file);},itemBuilder:(_)=>const [PopupMenuItem(value:'delete',child:Text('Delete'))]),
        )),
      ]);
    }));
  }
}

class StudyDocumentReader extends StatefulWidget {
  final StudyEntry entry;
  const StudyDocumentReader({super.key,required this.entry});
  @override State<StudyDocumentReader> createState()=>_StudyDocumentReaderState();
}
class _StudyDocumentReaderState extends State<StudyDocumentReader>{
  late Future<Uint8List> request;
  @override void initState(){super.initState();request=load();}
  Future<Uint8List> load()async{
    final path=widget.entry.data['storagePath']?.toString()??'';
    if(path.isEmpty)throw StateError('File has no Supabase Storage path');
    return Supabase.instance.client.storage.from('sp2_materials').download(path);
  }
  @override Widget build(BuildContext context){
    return Scaffold(appBar:AppBar(title:Text(widget.entry.title,maxLines:1,overflow:TextOverflow.ellipsis)),body:FutureBuilder<Uint8List>(future:request,builder:(context,snapshot){
      if(snapshot.hasError)return Center(child:Padding(padding:const EdgeInsets.all(20),child:Column(mainAxisSize:MainAxisSize.min,children:[
        Text('Could not load document: ${snapshot.error}'),const SizedBox(height:12),FilledButton(onPressed:()=>setState(()=>request=load()),child:const Text('Retry')),
      ])));
      if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
      final bytes=snapshot.data!;
      final ext=widget.entry.data['extension']?.toString().toLowerCase()??'';
      if(ext=='pdf')return PdfViewer.data(bytes, sourceName: widget.entry.id);
      if({'png','jpg','jpeg'}.contains(ext))return Center(child:InteractiveViewer(minScale:.5,maxScale:5,child:Image.memory(bytes,fit:BoxFit.contain)));
      try{
        final text=DocumentText.fromBytes(bytes,ext);
        return SelectionArea(child:ListView(padding:const EdgeInsets.all(20),children:[
          if({'docx','pptx'}.contains(ext))const Text('Reading view: extracted text; document layout is not preserved.',style:TextStyle(color:Colors.grey)),
          const SizedBox(height:12),Text(text.isEmpty?'This document contains no readable text.':text),
        ]));
      }catch(e){return Center(child:Text('This document cannot be decoded: $e'));}
    }));
  }
}
