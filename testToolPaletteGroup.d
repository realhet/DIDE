//@exe
import het, arsd.simpleaudio; 



void main()
{
	version(/+$DIDE_REGION Test MIDI   +/all)
	{
		{
			// Play a C major scale on the piano to demonstrate midi
			auto midi = MidiOutput(0); 
			
			ubyte[16] buffer = void; 
			ubyte[] where = buffer[]; 
			midi.writeRawMessageData(where.midiProgramChange(1, 1)); 
			for(ubyte note = MidiNote.C; note <= MidiNote.C + 12; note++)
			{
				where = buffer[]; 
				midi.writeRawMessageData(where.midiNoteOn(1, note, 127)); 
				sleep(500); 
				midi.writeRawMessageData(where.midiNoteOff(1, note, 127)); 
				
				if(note != 76 && note != 83)
				note++; 
			}
			sleep(500); // give the last note a chance to finish
		}
	}
	
	version(/+$DIDE_REGION Test WaveOut+/all)
	{
		{
			auto ao = AudioOutput(0, 48000); 
			double a=0, b=0; 
			ao.fillData = ((short[] buffer) {
				(mixin(求each(q{ref smp},q{buffer},q{smp=(cast(short)((itrunc(sin(b+=((sin(a+=0.00005))^^(2)))*8000))))}))); 
				if(a>20) ao.stop; 
			}); 
			ao.play; 
			
		}
	}
	
	version(/+$DIDE_REGION Test asynch MP3+/all)
	{
		{
			auto audio = AudioOutputThread(true); 
			audio	.playMp3(`c:\dl\Бьянка - Василёк (Альбом Волосы, 2019).mp3`)
				.seek(38); 
			sleep(10000); 
		}
	}
} 