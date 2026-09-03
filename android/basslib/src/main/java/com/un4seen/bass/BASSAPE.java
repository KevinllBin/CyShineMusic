/*
	BASSAPE 2.4 C/C++ header file
	Copyright (c) 2022-2023 Un4seen Developments Ltd.

	See the BASSAPE.CHM file for more detailed documentation
*/

package com.un4seen.bass;

import java.nio.ByteBuffer;
import android.os.ParcelFileDescriptor;

@SuppressWarnings({"all"})
public class BASSAPE
{
	// BASS_CHANNELINFO type
	public static final int BASS_CTYPE_STREAM_APE = 0x10700;

	public static native int BASS_APE_StreamCreateFile(String file, long offset, long length, int flags);
	public static native int BASS_APE_StreamCreateFile(ByteBuffer file, long offset, long length, int flags);
	public static native int BASS_APE_StreamCreateFile(BASS.Asset file, long offset, long length, int flags);
	public static native int BASS_APE_StreamCreateFile(ParcelFileDescriptor file, long offset, long length, int flags);
	public static native int BASS_APE_StreamCreateURL(String url, int offset, int flags, BASS.DOWNLOADPROC proc, Object user);
	public static native int BASS_APE_StreamCreateFileUser(int system, int flags, BASS.BASS_FILEPROCS procs, Object user);
	
	static {
		System.loadLibrary("bassape");
	}
}
