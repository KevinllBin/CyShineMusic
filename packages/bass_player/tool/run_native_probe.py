"""Run production GrooveShift sources on an authorized x86_64 emulator, without app/UI installation.
First run android/gradlew :bass_player:compileReleaseKotlin :basslib:bundleLibCompileToJarRelease.
"""
from pathlib import Path
import subprocess,os,zipfile,tempfile,uuid,struct,math
ROOT=Path(__file__).resolve().parents[3]
SDK=Path(os.environ['LOCALAPPDATA'])/'Android/Sdk'
def run(args,timeout=60):
    p=subprocess.run(list(map(str,args)),capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=timeout)
    if p.returncode:raise RuntimeError(p.stdout+'\n'+p.stderr)
    return p.stdout

def main():
    sdkjar=SDK/'platforms/android-36/android.jar';d8=SDK/'build-tools/37.0.0/lib/d8.jar'
    stdlib=next((Path(os.environ['USERPROFILE'])/'.gradle/caches/modules-2/files-2.1/org.jetbrains.kotlin/kotlin-stdlib/2.2.20').rglob('*.jar'))
    bass=ROOT/'build/basslib/intermediates/compile_library_classes_jar/release/bundleLibCompileToJarRelease/classes.jar'
    classes=ROOT/'build/bass_player/tmp/kotlin-classes/release'
    remote='/data/local/tmp/cyshine-groove-shift-'+uuid.uuid4().hex[:10]
    adb=['adb','-s','emulator-5554']
    with tempfile.TemporaryDirectory(prefix='cyshine-groove-shift-') as tmp:
        work=Path(tmp);out=work/'classes';out.mkdir()
        run(['javac','-encoding','UTF-8','--release','17','-cp',os.pathsep.join(map(str,[sdkjar,stdlib,bass,classes])),'-d',out,Path(__file__).with_name('GrooveShiftNativeProbe.java')])
        jar=work/'engine.jar'
        with zipfile.ZipFile(jar,'w') as z:
            for root in (classes,out):
                for f in root.rglob('*.class'):
                    if root==out or f.name.startswith(('GrooveShift','Mix','Gain','Effect','PlaybackDiagnostics')):z.write(f,f.relative_to(root))
        dex=work/'probe.zip'
        run(['java','-cp',d8,'com.android.tools.r8.D8','--release','--min-api','24','--lib',sdkjar,'--output',dex,jar,bass,stdlib])
        for name,bpm in [('a',120),('b',124),('mono',124),('fade',120)]:
            samples=bytearray();sr=22050 if name=='mono' else 44100;seconds=60;channels=1 if name=='mono' else 2
            for i in range(sr*seconds):
                t=i/sr;phase=(t-2)%(60/bpm);x=(.012*math.sin(2*math.pi*440*t)+.55*math.sin(2*math.pi*75*phase)*math.exp(-phase*55)) if 2<=t<seconds-2 else 0
                if name=='fade' and t>seconds-16:x*=10**(-(t-(seconds-16))*2/20)
                sample=int(x*32767);samples.extend(struct.pack('<h',sample)*channels)
            import wave
            with wave.open(str(work/(name+'.wav')),'wb') as w:w.setnchannels(channels);w.setsampwidth(2);w.setframerate(sr);w.writeframes(samples)
        run(adb+['shell','mkdir',remote])
        names=['probe.zip','a.wav','b.wav','mono.wav','fade.wav','libbass.so','libbass_fx.so','libbassmix.so']
        try:
            for n in names:
                source=ROOT/'android/basslib/src/main/jniLibs/x86_64'/n if n.endswith('.so') else work/n
                run(adb+['push',source,remote+'/'+n])
            output=run(adb+['shell',f'LD_LIBRARY_PATH={remote} CLASSPATH={remote}/probe.zip app_process64 /system/bin GrooveShiftNativeProbe {remote}'],60)
            print(output)
            if 'RESULT=success' not in output:raise RuntimeError('Native verification did not pass')
        finally:
            run(adb+['shell','rm','-f',*[remote+'/'+n for n in names]])
            run(adb+['shell','rmdir',remote])
if __name__=='__main__':main()
