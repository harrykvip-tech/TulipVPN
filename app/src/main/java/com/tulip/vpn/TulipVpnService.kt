package com.tulip.vpn
import android.content.Intent
import android.net.VpnService

class TulipVpnService:VpnService(){
 override fun onStartCommand(i:Intent?,f:Int,id:Int):Int{
  if(i?.action=="stop"){State.on=false;stopSelf();return START_NOT_STICKY}
  val cfg=i?.getStringExtra("config")?:return START_NOT_STICKY
  // sing-box libbox ချိတ်ရမယ့်နေရာ (libbox.aar လိုပါတယ်)
  State.on=true
  return START_STICKY}
 override fun onDestroy(){State.on=false}
}
