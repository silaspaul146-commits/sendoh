import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'main.dart' show apiProvider, money;

class CreateCollection extends ConsumerStatefulWidget {
  const CreateCollection({super.key});
  @override
  ConsumerState<CreateCollection> createState() => _CreateCollectionState();
}
class _CreateCollectionState extends ConsumerState<CreateCollection> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final description = TextEditingController();
  final target = TextEditingController();
  final expected = TextEditingController();
  final participant = TextEditingController();
  final List<String> people = [];
  String mode = 'ANY_AMOUNT';
  DateTime? deadline;
  int step = 0;
  bool busy = false;
  String? error;
  String key = List.generate(24, (_) => Random.secure().nextInt(16).toRadixString(16)).join();
  bool submitted = false;
  @override
  void dispose() { for(final c in [name,description,target,expected,participant]) { c.dispose(); } super.dispose(); }
  String? amount(String? value, {bool required = false}) {
    if(value == null || value.trim().isEmpty) return required ? 'Enter an amount' : null;
    final n=int.tryParse(value.trim());
    return n==null || n<=0 || n>1000000000000 ? 'Enter a positive whole FCFA amount' : null;
  }
  void changed() {
    if(submitted) { key=List.generate(24, (_) => Random.secure().nextInt(16).toRadixString(16)).join(); submitted=false; }
  }
  Future<void> save() async {
    setState(() { busy=true; error=null; submitted=true; });
    try {
      final data=await ref.read(apiProvider).request('/collections',key:key,body:{
        'name':name.text.trim(),'description':description.text.trim(),'currency':'XAF',
        'target_amount':target.text.trim().isEmpty?null:int.parse(target.text.trim()),
        'deadline_at':deadline?.toUtc().toIso8601String(),'mode':mode,
        'expected_amount':mode=='ANY_AMOUNT'?null:int.parse(expected.text.trim()),
        'participants':people.map((n)=>{'name':n}).toList(),'publish':true});
      if(mounted) Navigator.of(context).pop(Map<String,dynamic>.from(data));
    } catch(e) { if(mounted) setState(()=>error='$e'); }
    finally { if(mounted) setState(()=>busy=false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar:AppBar(title:const Text('Create collection')),body:SafeArea(child:Form(key:form,child:ListView(padding:const EdgeInsets.all(24),children:[
    Text('Step ${step+1} of 3 · ${['Details','Contribution','Review'][step]}'), const SizedBox(height:12),
    LinearProgressIndicator(value:(step+1)/3),const SizedBox(height:24),
    if(step==0)...[
      TextFormField(controller:name,maxLength:120,onChanged:(_)=>changed(),decoration:const InputDecoration(labelText:'Collection name'),validator:(v)=>v==null||v.trim().isEmpty?'Enter a name':null),
      const SizedBox(height:16),TextFormField(controller:description,maxLength:2000,maxLines:3,onChanged:(_)=>changed(),decoration:const InputDecoration(labelText:'Purpose (optional)')),
      const SizedBox(height:16),TextFormField(controller:target,keyboardType:TextInputType.number,onChanged:(_)=>changed(),validator:(v)=>amount(v),decoration:const InputDecoration(labelText:'Target in FCFA (optional)')),
      const SizedBox(height:16),ListTile(contentPadding:EdgeInsets.zero,title:Text(deadline==null?'No deadline':'Deadline: ${deadline!.year}-${deadline!.month}-${deadline!.day}'),
        trailing:TextButton(onPressed:() async { final d=await showDatePicker(context:context,initialDate:deadline??DateTime.now(),firstDate:DateTime.now().subtract(const Duration(days:1)),lastDate:DateTime.now().add(const Duration(days:3650))); if(d!=null) {changed();setState(()=>deadline=DateTime(d.year,d.month,d.day,23,59));} },child:const Text('Choose'))),
      if(deadline!=null) TextButton(onPressed:(){changed();setState(()=>deadline=null);},child:const Text('Remove deadline')),
      const Text('A deadline is a reminder. It does not automatically close the collection.'),
    ],
    if(step==1)...[
      DropdownButtonFormField<String>(value:mode,decoration:const InputDecoration(labelText:'Contribution rule'),items:const [
        DropdownMenuItem(value:'ANY_AMOUNT',child:Text('Any amount')),
        DropdownMenuItem(value:'EXPECTED_TOTAL',child:Text('Expected total per person')),
        DropdownMenuItem(value:'MINIMUM_TOTAL',child:Text('Minimum total per person'))],onChanged:(v){changed();setState(()=>mode=v!);}),
      if(mode!='ANY_AMOUNT')... [const SizedBox(height:16),TextFormField(controller:expected,onChanged:(_)=>changed(),keyboardType:TextInputType.number,validator:(v)=>amount(v,required:true),decoration:const InputDecoration(labelText:'Amount per person in FCFA'))],
      const SizedBox(height:24),Text('Participants (optional)',style:Theme.of(context).textTheme.titleMedium),const SizedBox(height:12),
      TextField(controller:participant,maxLength:120,decoration:InputDecoration(labelText:'Participant name',suffixIcon:IconButton(icon:const Icon(Icons.add),onPressed:(){if(participant.text.trim().isNotEmpty && people.length<200){changed();setState(()=>people.add(participant.text.trim()));participant.clear();}}))),
      ...people.asMap().entries.map((e)=>ListTile(title:Text(e.value),trailing:IconButton(icon:const Icon(Icons.close),onPressed:(){changed();setState(()=>people.removeAt(e.key));}))),
      const Text('Participants can contribute in installments. This build supports up to 200 initial participants.'),
    ],
    if(step==2)...[
      Text(name.text,style:Theme.of(context).textTheme.headlineSmall),const SizedBox(height:16),Text(description.text),
      const SizedBox(height:16),Text('Target: ${target.text.trim().isEmpty?'No target':money(int.parse(target.text.trim()))}'),
      Text('Deadline: ${deadline==null?'None':deadline.toString()}'),
      Text('Contribution: ${mode=='ANY_AMOUNT'?'Any amount':money(int.parse(expected.text.trim()))}'),
      Text('${people.length} participants'),const SizedBox(height:24),
      const Text('Anyone with the collection link can view its public details. Participant names are not included on the public page.'),
      const SizedBox(height:12),const Text('Creating a collection is free. Payment and settlement functionality is not enabled in this build.'),
    ],
    if(error!=null) Padding(padding:const EdgeInsets.symmetric(vertical:16),child:Text(error!,style:const TextStyle(color:Colors.red))),
    const SizedBox(height:24),FilledButton(onPressed:busy?null:(){if(step<2){if(form.currentState!.validate()) setState(()=>step++);}else{save();}},child:Text(busy?'Creating…':step==2?'Create collection':'Continue')),
    if(step>0) TextButton(onPressed:busy?null:()=>setState(()=>step--),child:const Text('Back')),
  ]))));
}
