%function abfconv()
disp('**CHOOSE AN .ABF FILE AND MAKE SURE TO HIGHLIGHT ALL DESIRED CHANNELS BEFORE IMPORTING');
    % Filter out HF (~9 kHz) noise common in ABF files
	fwrite (fid,scaledad0,'int16');