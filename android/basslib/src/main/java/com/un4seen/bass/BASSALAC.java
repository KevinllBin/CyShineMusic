/*
	BASSALAC 2.4 C/C++ header file
	Copyright (c) 2016-2024 Un4seen Developments Ltd.

	See the BASSALAC.CHM file for more detailed documentation
*/

package com.un4seen.bass;

import java.nio.ByteBuffer;
import android.os.ParcelFileDescriptor;

@SuppressWarnings({"all"})
public class BASSALAC
{
	// BASS_CHANNELINFO type
	public static final int BASS_CTYPE_STREAM_ALAC = 0x10e00;

	public static native int BASS_ALAC_StreamCreateFile(String file, long offset, long length, int flags);
	public static native int BASS_ALAC_StreamCreateFile(ByteBuffer file, long offset, long length, int flags);
	public static native int BASS_ALAC_StreamCreateFile(BASS.Asset file, long offset, long length, int flags);
	public static native int BASS_ALAC_StreamCreateFile(ParcelFileDescriptor file, long offset, long length, int flags);
	public static native int BASS_ALAC_StreamCreateURL(String url, int offset, int flags, BASS.DOWNLOADPROC proc, Object user);
	public static native int BASS_ALAC_StreamCreateFileUser(int system, int flags, BASS.BASS_FILEPROCS procs, Object user);
	
	static {
		System.loadLibrary("bassalac");
	}
}
