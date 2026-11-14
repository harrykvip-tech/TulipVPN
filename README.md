# Tulip VPN

ကိုယ်ပိုင်သုံး V2Ray/Xray VPN client (Android)။ Flutter + Xray core။

- VLESS · VMess · Trojan · Shadowsocks · Outline (`ss://`, `ssconf://`) · SOCKS · Hysteria2 key အားလုံးထည့်သုံးနိုင်
- Subscription link (http/https) နဲ့ JSON config လည်း ထည့်နိုင်
- Key အများကြီး တစ်ခါတည်း paste လုပ်နိုင် (တစ်ကြောင်းတစ်ခု)
- **QR code** ကင်မရာနဲ့ scan လုပ်ပြီး key ထည့်နိုင်၊ server တစ်ခုချင်းရဲ့ QR ပြန်ထုတ်ပြီး မျှဝေနိုင်
- **Per-app proxy**: ရွေးထားတဲ့ app တွေကို VPN ကျော်ခိုင်း (ဥပမာ banking app) သို့မဟုတ် ရွေးထားတဲ့ app တွေပဲ VPN သုံးခိုင်း
- Server တစ်ခုချင်းကို field အလိုက် (address, port, id, network, TLS/Reality…) ပြင်နိုင်
- Ping စစ်ပြီး အမြန်ဆုံး server ကို အလိုအလျောက်ရွေးနိုင်
- **Home Screen Widget** (2×1) နဲ့ **Quick Settings Tile**: app ထဲမဝင်ဘဲ On/Off လုပ်နိုင် (VPN permission တစ်ခါပေးပြီးရင် app မဖွင့်ဘဲ နောက်ကွယ်မှာ ဖွင့်/ပိတ်ပေးတယ်)
- **Server flag** (နိုင်ငံအလံ) နဲ့ **Delay color coding**: 🟢 <300ms · 🟡 <700ms · 🔴 နှေး/timeout
- **Subscription card**: link တစ်ခုချင်းကို group ခွဲပြပြီး အသုံးပြုထားတဲ့ data (`25.5 MB / 1.0 TB`)၊ ကျန်ရက် (`88 Days Left`)၊ Update (⟳)၊ Ping (speedometer) နဲ့ ဖျက်လို့ရ။ Link အများကြီး ထည့်နိုင်
- **All / Subscription** filter chip နဲ့ server tile (protocol အစင်းဘေးမှာ၊ host ကို `sore****.com` လို ဖုံး၊ ping pill)။ Tile ကို ကြာကြာနှိပ်ရင် Edit / QR / Copy / Delete
- Light / Dark / System theme၊ Liquid Glass UI
- Tulip logo (`assets/icon.png`) ကို app icon အဖြစ် သုံးထား

## GitHub မှာ APK ထုတ်နည်း

1. GitHub မှာ repo အသစ်ဆောက်ပြီး ဒီ folder ထဲက ဖိုင်အားလုံး push လုပ်ပါ
   (`.github`, `assets`, `lib`, `scripts`, `pubspec.yaml`, `.gitignore`, `README.md`)
2. `main` branch ကို push လုပ်တာနဲ့ **Actions → Build Tulip VPN APK** အလိုအလျောက်ပြေးမယ်
   (ကိုယ်တိုင်ပြေးချင်ရင် **Run workflow**)
3. ပြီးရင် run ထဲက **Artifacts → Tulip-VPN-apk** ကနေ zip ဒေါင်းပြီး ထဲက `Tulip-VPN.apk` ကို install လုပ်ပါ
4. Release အဖြစ်ထုတ်ချင်ရင်: `git tag v1.0.0 && git push --tags`
   → **Releases** မှာ APK ပေါ်လာမယ်

## Widget / Quick Tile သုံးနည်း

- **Widget**: Home screen ကို ကြာကြာနှိပ် → Widgets → Tulip VPN ကို ထည့်ပါ
- **Quick Tile**: Notification panel ကို အပြည့်ဆွဲချ → ✏️ (Edit) → Tulip VPN tile ကို ဆွဲထည့်ပါ
- VPN permission ပထမဆုံးတစ်ခါ ခွင့်ပြုထားဖို့ app ထဲက အရင် Connect လုပ်ကြည့်ပါ (အဲဒီအထိ tile/widget က app ကို ဖွင့်မယ်)
- Flag ကို server နာမည်ထဲက အလံ/နိုင်ငံနာမည်/`SG` `US` လို code သို့မဟုတ် domain TLD (`.sg`, `.jp`) ကနေ သိတာပါ။ မသိရင် 🌐 ပြမယ်။ နာမည်ကို Edit ထဲက `SG - Singapore 01` လို ပေးထားရင် အသေချာဆုံး

## မှတ်ချက်

- CI ကနေ ထုတ်တဲ့ APK ကို debug key နဲ့ sign လုပ်ထားပါတယ်။ build တစ်ခုနဲ့တစ်ခု key မတူနိုင်လို့
  update တင်တဲ့အခါ "App not installed" ပေါ်ရင် အဟောင်းကို အရင် uninstall လုပ်ပါ
  (key တွေ အရင် copy ကူးထား)။ တစ်သမတ်တည်း update လိုချင်ရင် ကိုယ်ပိုင် keystore ထည့်ပါ။
- App က VPN client သာဖြစ်ပြီး server/key ကို ကိုယ့်ဘာသာ ပေးရပါမယ်။
