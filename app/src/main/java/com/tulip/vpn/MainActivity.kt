package com.tulip.vpn
import android.content.Intent
import android.content.SharedPreferences
import android.net.VpnService
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.*
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.*

class MainActivity:ComponentActivity(){
 override fun onCreate(b:Bundle?){super.onCreate(b);setContent{App(this,getSharedPreferences("t",0))}}
}

@Composable fun C(content:@Composable ColumnScope.()->Unit){
 Card(Modifier.fillMaxWidth().padding(vertical=6.dp),RoundedCornerShape(24.dp)){Column(Modifier.padding(16.dp),content=content)}}

@Composable fun App(ctx:ComponentActivity,sp:SharedPreferences){
 var theme by remember{mutableStateOf(2)}
 val dark=theme==2||(theme==0&&isSystemInDarkTheme())
 val servers=remember{mutableStateListOf<Server>().apply{addAll(sp.getString("links","")!!.lines().mapNotNull{Core.parse(it)})}}
 var sel by remember{mutableStateOf(0)};var tab by remember{mutableStateOf(0)};var dlg by remember{mutableStateOf(false)}
 var sub by remember{mutableStateOf<Core.Sub?>(null)}
 fun save(){sp.edit().putString("links",servers.joinToString("\n"){it.link}).apply()}
 val perm=rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()){if(it.resultCode==-1)Core.start(ctx,servers[sel])}
 fun toggle(){
  if(State.on)ctx.startService(Intent(ctx,TulipVpnService::class.java).setAction("stop"))
  else if(servers.isNotEmpty()){val i=VpnService.prepare(ctx);if(i!=null)perm.launch(i)else Core.start(ctx,servers[sel])}}
 fun add(t:String){Thread{try{
  if(t.startsWith("http")){val s=Core.fetchSub(t);sub=s;s.links.mapNotNull{Core.parse(it)}.forEach{servers.add(it)}}
  else Core.parse(t)?.let{servers.add(it)}
  save()}catch(e:Exception){}}.start()}
 fun pingAll(){Thread{
  servers.indices.forEach{i->servers[i]=servers[i].copy(ping=Core.ping(servers[i]))}
  servers.indices.filter{servers[it].ping>0}.minByOrNull{servers[it].ping}?.let{sel=it}}.start()}

 MaterialTheme(colorScheme=if(dark)darkColorScheme()else lightColorScheme()){
  val bg=if(dark)listOf(Color(0xFF0B1D33),Color(0xFF1A1240),Color(0xFF0B2230))else listOf(Color(0xFFC4DAFD),Color(0xFFD8D2F8),Color(0xFFB9F0EC))
  Scaffold(Modifier.background(Brush.verticalGradient(bg)),containerColor=Color.Transparent,
   bottomBar={NavigationBar(containerColor=Color.Transparent){
    listOf("Home" to Icons.Filled.Home,"Config" to Icons.Filled.Tune,"Data" to Icons.Filled.BarChart,"Settings" to Icons.Filled.Settings)
     .forEachIndexed{i,(n,ic)->NavigationBarItem(tab==i,{tab=i},{Icon(ic,n)},label={Text(n,fontSize=12.sp)})}}}
  ){pad->
   Column(Modifier.padding(pad).padding(16.dp).verticalScroll(rememberScrollState())){
    Row(verticalAlignment=Alignment.CenterVertically){
     Text("🌷 Tulip VPN",fontSize=22.sp,fontWeight=FontWeight.SemiBold,modifier=Modifier.weight(1f))
     IconButton({dlg=true}){Icon(Icons.Filled.Add,"Add")}}
    when(tab){
     0->{
      C{Text("CONNECTION",fontSize=12.sp)
       Row(verticalAlignment=Alignment.CenterVertically){
        Column(Modifier.weight(1f)){
         Text(if(State.on)"Connected" else "Not connected",fontSize=26.sp,fontWeight=FontWeight.Medium)
         Text(servers.getOrNull(sel)?.name?:"No server",fontSize=14.sp)}
        Switch(State.on,{toggle()})}}
      sub?.let{s->C{
       Text("Subscription (${servers.size})",fontSize=16.sp)
       LinearProgressIndicator({if(s.total>0)s.used.toFloat()/s.total else 0f},Modifier.fillMaxWidth().padding(vertical=8.dp))
       val days=if(s.expire>0)(s.expire*1000-System.currentTimeMillis())/86400000 else 0
       Text("${s.used/1048576} MB / ${s.total/1073741824} GB  ·  $days Days Left",fontSize=12.sp)}}
      Text("SERVERS",fontSize=12.sp,modifier=Modifier.padding(top=12.dp,start=6.dp))
      servers.forEachIndexed{i,s->
       Card(Modifier.fillMaxWidth().padding(vertical=6.dp).clickable{sel=i},RoundedCornerShape(22.dp),
        CardDefaults.cardColors(if(i==sel)MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface)){
        Row(Modifier.height(IntrinsicSize.Min)){
         Box(Modifier.width(30.dp).fillMaxHeight().background(Color(0xFF0891C4)),Alignment.Center){
          Text(s.proto,fontSize=10.sp,color=Color.White,modifier=Modifier.rotate(-90f).requiredWidth(60.dp),maxLines=1,textAlign=androidx.compose.ui.text.style.TextAlign.Center)}
         Column(Modifier.padding(14.dp)){
          Text(s.name,fontSize=16.sp)
          Spacer(Modifier.height(10.dp))
          Text("${s.host}   ${if(s.ping>0)"${s.ping} ms" else "—"}",fontSize=13.sp)}}}}
      C{Text("⚡ Ping all · pick fastest",fontSize=15.sp,modifier=Modifier.clickable{pingAll()})}}
     1->{
      Text("KEYS",fontSize=12.sp,modifier=Modifier.padding(6.dp))
      C{Text("🔗 Add key or subscription",Modifier.clickable{dlg=true}.fillMaxWidth().padding(8.dp))
        Text("VLESS · Trojan · subscription URL",fontSize=12.sp)
        Text("🗑 Delete all servers",color=Color(0xFFF87171),modifier=Modifier.clickable{servers.clear();sub=null;save()}.fillMaxWidth().padding(8.dp))}
      C{Text("Ping all servers",Modifier.clickable{pingAll()}.fillMaxWidth().padding(8.dp))
        Text("Pick fastest server",Modifier.clickable{pingAll()}.fillMaxWidth().padding(8.dp))}
      C{Text("Developer",fontSize=12.sp);Text("Tulip VPN",fontSize=17.sp)}}
     2->C{
      Text("THIS SESSION",fontSize=12.sp)
      Text("Status: ${if(State.on)"Connected" else "Not connected"}",Modifier.padding(8.dp))
      Text("Server: ${servers.getOrNull(sel)?.name?:"-"}",Modifier.padding(8.dp))
      sub?.let{Text("Used: ${it.used/1048576} MB",Modifier.padding(8.dp))}}
     else->{
      C{Text("Per-app proxy: Off",Modifier.padding(8.dp))}
      C{listOf("System","Light","Dark").forEachIndexed{i,n->
        Row(Modifier.fillMaxWidth().clickable{theme=i}.padding(8.dp)){Text(n,Modifier.weight(1f));if(theme==i)Icon(Icons.Filled.Check,null)}}}
      C{Text("Tulip VPN 1.4",fontSize=16.sp);Text("sing-box client for Android",fontSize=13.sp)}}}}}
  if(dlg){var t by remember{mutableStateOf("")}
   AlertDialog({dlg=false},confirmButton={TextButton({add(t);dlg=false}){Text("Add")}},
    dismissButton={TextButton({dlg=false}){Text("Cancel")}},title={Text("Add key or subscription")},
    text={OutlinedTextField(t,{t=it},placeholder={Text("vless:// trojan:// or https://…")})})}}
}
