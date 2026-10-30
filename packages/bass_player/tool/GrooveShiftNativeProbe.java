import android.content.Context;
import android.os.Handler;
import android.os.HandlerThread;
import com.cyshine.bass_player.GrooveShiftEngine;
import com.un4seen.bass.BASS;
import com.un4seen.bass.BASSmix;
import java.nio.*;
import java.util.*;
import java.util.concurrent.*;
import kotlin.Unit;

/** Runs the production decoder/analysis/planner/mixer in the no-sound device. No app installation. */
public class GrooveShiftNativeProbe {
  static GrooveShiftEngine engine;
  static Handler handler;
  static int mixer;
  static boolean acceptReservations=true;
  static List<String> events=new CopyOnWriteArrayList<>();
  static void onEngine(Runnable action)throws Exception {
    CountDownLatch done=new CountDownLatch(1);final Throwable[] error={null};
    handler.post(()->{try{action.run();}catch(Throwable e){error[0]=e;}finally{done.countDown();}});
    if(!done.await(15,TimeUnit.SECONDS))throw new AssertionError("engine timeout");
    if(error[0]!=null)throw new RuntimeException(error[0]);
  }
  static void check(boolean ok,String message){if(!ok)throw new AssertionError(message+" bass="+BASS.BASS_ErrorGetCode());}
  static long renderUntil(String target,long maxBytes)throws Exception {
    ByteBuffer pcm=ByteBuffer.allocateDirect(65536).order(ByteOrder.nativeOrder());long bytes=0;double energy=0;
    while(bytes<maxBytes && !events.contains(target)){
      pcm.clear();int n=BASS.BASS_ChannelGetData(mixer,pcm,65536);
      if(n<0)break;
      if(n==0)throw new AssertionError("mixer stalled");
      bytes+=n;
      for(int i=0;i<n/4;i++){double x=pcm.getFloat(i*4);check(Double.isFinite(x),"invalid PCM");energy+=x*x;}
      onEngine(()->{});
    }
    System.out.println("RENDER bytes="+bytes+" energy="+energy+" target="+target);
    return bytes;
  }
  static long renderTail(long maxBytes)throws Exception {
    ByteBuffer pcm=ByteBuffer.allocateDirect(65536).order(ByteOrder.nativeOrder());long bytes=0;
    while(bytes<maxBytes){
      pcm.clear();int n=BASS.BASS_ChannelGetData(mixer,pcm,65536);
      if(n<=0)break;
      bytes+=n;
      for(int i=0;i<n/4;i++)check(Double.isFinite(pcm.getFloat(i*4)),"invalid tail PCM");
      onEngine(()->{});
    }
    return bytes;
  }
  static void prepare(String first,String second,String id)throws Exception{
    events.clear();onEngine(()->{engine.close();if(mixer!=0)BASS.BASS_StreamFree(mixer);mixer=engine.load(first);engine.configure(true);engine.next(id,second);});
    long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(20);
    while(!events.contains("planned") && System.nanoTime()<deadline)Thread.sleep(10);
    check(events.contains("planned"),"analysis/plan missing");onEngine(()->{});
  }
  public static void main(String[] args)throws Exception {
    try{
      System.load(args[0]+"/libbass.so");System.load(args[0]+"/libbass_fx.so");System.load(args[0]+"/libbassmix.so");
      check(BASS.BASS_Init(0,44100,0),"no-sound init");
      HandlerThread thread=new HandlerThread("native-probe-engine");thread.start();handler=new Handler(thread.getLooper());
      android.os.Looper.prepareMainLooper();
      Class<?> at=Class.forName("android.app.ActivityThread");Object activity=at.getMethod("systemMain").invoke(null);Context context=(Context)at.getMethod("getSystemContext").invoke(activity);
      engine=new GrooveShiftEngine(context,handler,(path,flags)->BASS.BASS_StreamCreateFile(path,0,0,flags),(phase,id,details)->{
        events.add(phase);System.out.println("EVENT "+phase+" "+id+" "+details);
        if(phase.equals("reserve") && acceptReservations)engine.confirm(id);
        return Unit.INSTANCE;
      });
      String first=args[0]+"/a.wav",second=args[0]+"/b.wav";
      prepare(first,second,"full");renderUntil("finished",44100L*8*100);
      check(events.contains("reserve") && events.contains("handoff") && events.contains("finished"),"full lifecycle missing "+events);
      renderTail(44100L*8*100);
      onEngine(()->check(Math.abs(engine.position()-engine.duration())<50,"end clock reset: "+engine.position()+"/"+engine.duration()));
      onEngine(()->{check(engine.seek(10000),"seek incoming");check(Math.abs(engine.position()-10000)<50,"incoming clock");});
      prepare(first,args[0]+"/mono.wav","mono-resample");renderUntil("finished",44100L*8*100);check(events.contains("finished"),"mono transition");
      prepare(args[0]+"/fade.wav",second,"fade");renderUntil("finished",44100L*8*100);check(events.contains("finished"),"fade transition");
      prepare(first,second,"cancel-active");renderUntil("started",44100L*8*65);check(events.contains("started"),"mix never started");onEngine(()->engine.cancel("probe"));renderUntil("handoff",44100L*8*20);check(!events.contains("handoff"),"active cancel leaked handoff");
      acceptReservations=false;prepare(first,second,"unconfirmed");renderUntil("cancelled",44100L*8*65);check(!events.contains("started") && !events.contains("handoff"),"unconfirmed transition started");acceptReservations=true;
      prepare(first,second,"cancel-before");onEngine(()->engine.cancel("probe"));renderUntil("finished",44100L*8*65);
      check(!events.contains("handoff"),"cancel leaked handoff");
      prepare(first,second,"seek-before");onEngine(()->check(engine.seek(3000),"seek outgoing"));check(events.contains("cancelled"),"seek failed to cancel");
      prepare(first,second,"cancel-after");renderUntil("handoff",44100L*8*65);check(events.contains("handoff"),"handoff missing");
      onEngine(()->{engine.cancel("probe");check(engine.seek(9000),"seek after handoff");check(Math.abs(engine.position()-9000)<50,"clock after handoff");});
      onEngine(()->{engine.dispose();BASS.BASS_StreamFree(mixer);BASS.BASS_Free();});thread.quitSafely();
      System.out.println("RESULT=success");System.exit(0);
    }catch(Throwable e){e.printStackTrace();System.out.println("RESULT=failed");System.exit(1);}
  }
}
