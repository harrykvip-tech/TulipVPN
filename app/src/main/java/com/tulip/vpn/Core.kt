package com.tulip.vpn
import android.content.Context
import android.content.Intent
import android.util.Base64
import androidx.compose.runtime.*
import org.json.*
import java.net.*

object State{ var on by mutableStateOf(false) }
data class Server(val link:String,val name:String,val proto:String,val host:String,val port:Int,val ping:Int=-1)

object Core{
 class Sub(val links:List<String>,val used:Long,val total:Long,val expire:Long)
 fun parse(link:String):Server?=try{
  val u=URI(link.trim()); Server(link.trim(),URLDecoder.decode(u.fragment?:u.host,"UTF-8"),u.scheme.uppercase(),u.host,u.port)
 }catch(e:Exception){null}
 private fun q(u:URI)=(u.rawQuery?:"").split("&").filter{it.contains("=")}.associate{it.substringBefore("=") to URLDecoder.decode(it.substringAfter("="),"UTF-8")}
 fun outbound(link:String):JSONObject{
  val u=URI(link);val q=q(u);val t=u.scheme.lowercase()
  val o=JSONObject().put("tag","proxy").put("type",t).put("server",u.host).put("server_port",u.port)
  if(t=="vless"){o.put("uuid",u.userInfo);q["flow"]?.let{o.put("flow",it)}}else o.put("password",u.userInfo)
  val sec=q["security"]?:(if(t=="trojan")"tls" else "none")
  if(sec!="none"){
   val tls=JSONObject().put("enabled",true).put("server_name",q["sni"]?:u.host)
   q["fp"]?.let{tls.put("utls",JSONObject().put("enabled",true).put("fingerprint",it))}
   if(sec=="reality")tls.put("reality",JSONObject().put("enabled",true).put("public_key",q["pbk"]).put("short_id",q["sid"]?:""))
   o.put("tls",tls)}
  if(q["type"]=="ws")o.put("transport",JSONObject().put("type","ws").put("path",q["path"]?:"/").put("headers",JSONObject().put("Host",q["host"]?:u.host)))
  return o}
 fun config(link:String)=JSONObject().put("log",JSONObject().put("level","warn"))
  .put("inbounds",JSONArray().put(JSONObject().put("type","tun").put("address",JSONArray().put("172.19.0.1/30")).put("auto_route",true).put("stack","mixed")))
  .put("outbounds",JSONArray().put(outbound(link)).put(JSONObject().put("type","direct").put("tag","direct")))
  .put("route",JSONObject().put("auto_detect_interface",true).put("final","proxy")).toString()
 fun fetchSub(url:String):Sub{
  val c=URL(url).openConnection() as HttpURLConnection
  val body=c.inputStream.bufferedReader().readText().trim()
  val info=(c.getHeaderField("subscription-userinfo")?:"").split(";").map{it.trim().split("=")}.filter{it.size==2}.associate{it[0] to (it[1].toLongOrNull()?:0L)}
  val text=if(body.contains("://"))body else String(Base64.decode(body,Base64.DEFAULT))
  return Sub(text.lines().filter{it.contains("://")},(info["upload"]?:0L)+(info["download"]?:0L),info["total"]?:0L,info["expire"]?:0L)}
 fun ping(s:Server):Int=try{val t=System.nanoTime();Socket().use{it.connect(InetSocketAddress(s.host,s.port),3000)};((System.nanoTime()-t)/1000000).toInt()}catch(e:Exception){-1}
 fun start(c:Context,s:Server){c.startService(Intent(c,TulipVpnService::class.java).putExtra("config",config(s.link)))}
}
