function RunPeriTaskMonkey(show)
% RunPeriTaskMonkey(show)
% This program tests for significant changes in firing around movement
% onset
% Created by RST, 2005-08-22
% Revised by RST, 2006-11-27 - Use Dystonia Rig strobed events in NEX file
% Revised by Sho 2008-02-05 alignment-specific txt/mat file naming
% and save EMF graph files 
%
%	Input:
%		show - controls whether graphical output is produced for each cell
%		  default = true.
%
%	Run within a directory and this program will process all spikes in all 
%	nex files in the directory
%
%   Assumes NEX files contain spikes & strobed events
%	

% Global defines used by the other functions called by this one
global PRE_MVT
global PST_MVT
global CNTL_PER
% global MAX_N
global ALPHA
global CONTIG

% global SRCH_LO
% global SRCH_HI
global VERBOSE

PRE_MVT = -1.5;
PST_MVT = 1;
SMOOTH = 50;	% SD of smoothing gaussian (in msec)
CNTL_PER = [-1.5 -0.5];
%ALPHA = 0.05;
% sig. level needs to be DECREASED
ALPHA = 0.01;
CONTIG = 50;	% Mean of 'CONTIG' adjacent points must be significant
JOIN = 0.2;		% Join together responses that are < JOIN sec apart
MIN_SPK_N = 500;
EVENTS = { 'QUIT PROGRAM' 'home' 'light' 'move' 'touch' 'reward'};

VERBOSE=false;

N_Pks = 2;	% max # of significant changes

if ~exist('show','var')
	show = true;
end

% Edit this pattern to select time-stamp variables w/ specific names
% spkname_pattern = 'sig\w*[abcd]';	% All sorted snips (ignor unsorted ="U")
spkname_pattern = '\w*';	% Accept all units

cd(uigetdir);

FileLst = dir('*.nex');
if(isempty(FileLst))
	str = pwd;
	error(['Found no NEX files in current directory - ' str ]);
end

% Simple way to select alignment event - same alignment used for all files
% processed in one batch
evt_n = menu('Choose alignment event', EVENTS);
align_select = EVENTS{evt_n};
if evt_n ==1	% 1 = 'quit'
	return
end

outfid = write_text_header(N_Pks,align_select);	% Subfunction (below) initializes text file



n = 0;	% Count of units processed
% For each file found in directory...
for i=1:length(FileLst)

	nexname = FileLst(i).name;
    [pth,fname,ext] = fileparts(nexname);

	% Find variables of interest in NEX file
    info = nex_info_rst(nexname,VERBOSE);
    data_start = 0;
    data_stop = info.dur;
	[spk_inds,spk_names] = find_nex_units( nexname, spkname_pattern);
	spk_menu = [ 'Quit' ; cellstr( deblank(spk_names) ) ];
	if isempty(spk_inds)
		display(['Found no units in file:  ' nexname '. Skipping']);
		continue
	end

	events = GetNexStrobedEvents(nexname);
	if isempty(events) 
		display(['Found no ''events'' in file: ' nexfile '. Skipping.']);
		continue
	elseif length(unique(events.target))==1
		display(['Found only 1 mvt direction in file: ' nexname '. Continuing']);
	end

	L_inds = find(events.target == 'L' & events.success);
	R_inds = find(events.target == 'R' & events.success);

	tmp_evt = events.(EVENTS{evt_n});
	Evt(1).ts = tmp_evt(L_inds);
	Evt(1).n = length(Evt(1).ts);
	Evt(2).ts = tmp_evt(R_inds);
	Evt(2).n = length(Evt(2).ts);
	
    for k=1:length(Evt)		% Filter out events too close to data boundaries
		drp = find(Evt(k).ts < data_start-PRE_MVT | Evt(k).ts > data_stop-PST_MVT);
		Evt(k).ts(drp) = [];
		Evt(k).n = length(Evt(k).ts);
	end	

	spk_ind = menu({['File:..' fname]; 'Select a unit to process'}, spk_menu);
	% For each unit in a file...
	while spk_ind>1 	% spk_ind==1 means "quit"
		n = n+1;
		spk{n}.fname = fname;
		spk{n}.align_evt = EVENTS{evt_n};
		
		% save name of file & unit
		spk{n}.unitname = spk_menu{spk_ind};
		display(['Processing...' spk{n}.fname '....:' spk{n}.unitname]);
		
		% get spike times
		[spk_n, spk_t] = nex_ts( nexname, spk{n}.unitname,VERBOSE);
		if spk_n < MIN_SPK_N
			display(['Found only ' num2str(spk_n) ' spikes. Skipping.']);
			continue
		end

		% for each direction of movement
		for k=1:length(Evt)
			spk{n}.dir(k).n_reps = Evt(k).n;
			

			[spk{n}.dir(k).histog, spk{n}.bins] = perievent_sdf(spk_t, Evt(k).ts, ...
				PRE_MVT, PST_MVT, SMOOTH );

			spk{n}.dir(k).raster = perievent_raster(spk_t, Evt(k).ts, ...
				PRE_MVT, PST_MVT);

			cntl_inds = find(spk{n}.bins>=CNTL_PER(1) & spk{n}.bins<CNTL_PER(2));
			test_start = max(cntl_inds)+1;
			
			[spk{n}.dir(k).chng(1),spk{n}.dir(k).cntl_mean,spk{n}.dir(k).sig_thr] = ...
				PeriEventChange_SDF(spk{n}.dir(k).histog,cntl_inds,test_start,ALPHA,CONTIG);
			
			sgn1 = spk{n}.dir(k).chng(1).sgn;
			sgn2 = [];
			del2nd = 0;
			if ~isempty( spk{n}.dir(k).chng(1).off_ind )
				test_start = spk{n}.dir(k).chng(1).off_ind;
 				[spk{n}.dir(k).chng(2),spk{n}.dir(k).cntl_mean,q] = ...
 					PeriEventChange_SDF(spk{n}.dir(k).histog,cntl_inds,test_start,ALPHA,CONTIG);
				sgn2 = spk{n}.dir(k).chng(2).sgn;
			end
			if sgn2==sgn1
				off1_t = spk{n}.bins( spk{n}.dir(k).chng(1).off_ind ) ;
				on2_t = spk{n}.bins( spk{n}.dir(k).chng(2).on_ind ) ;
				if (on2_t - off1_t)< JOIN
					on1_ind = spk{n}.dir(k).chng(1).on_ind ;
					off1_ind = spk{n}.dir(k).chng(2).off_ind ;
					spk{n}.dir(k).chng(1).off_ind = off1_ind;
					his = spk{n}.dir(k).histog - spk{n}.dir(k).cntl_mean;
					if ~isempty(off1_ind)
						spk{n}.dir(k).chng(1).mean_change = ...
							mean( his(on1_ind:off1_ind) );
						spk{n}.dir(k).chng(1).int_change = ...
							sum( his(on1_ind:off1_ind) )/1000;
					else
						spk{n}.dir(k).chng(1).mean_change = ...
							mean( his(on1_ind:end) );
						spk{n}.dir(k).chng(1).int_change = ...
							sum( his(on1_ind:end) )/1000;
					end
					del2nd = 1;
				end
			end
			if isempty( spk{n}.dir(k).chng(1).off_ind ) | del2nd
				spk{n}.dir(k).chng(2).on_ind = [];
				spk{n}.dir(k).chng(2).sgn = [];
				spk{n}.dir(k).chng(2).off_ind = [];
				spk{n}.dir(k).chng(2).mean_change = [];
				spk{n}.dir(k).chng(2).int_change = [];
			end
		end
		if( show)
			make_figure(spk{n},N_Pks, align_select);
		end
				
		% write stats to file
		write_text(outfid,spk{n},N_Pks);
		
		% delete processed spike from menu
		spk_menu(spk_ind) = [];
		% get next spike or choose 'quit'
		if length(spk_menu)>1
			spk_ind = menu('Choose unit to process', spk_menu);
		else
			break
		end
end
end
fclose(outfid);

if exist('spk','var')
    outfname = ['PeriORTask_' align_select];
	save(outfname, 'spk');
end

%------------------------------------------------------
% Subfunction to make figure of results
function make_figure(s, N_Pks, align_select)
	bins = s.bins;
	
	%%%%%%%%%%%%%% Plotting
	% Set up axes
	MARGIN = 0.06;	
	TOP = 1-MARGIN;		% Top margin of page
	LEFT = MARGIN;	% Left margin of page
	WIDTH = (1-3*MARGIN)/2;	% give space for 3 margin widths including middle
	HEIGHT = 0.4;	% Height of histograms
	CLR = [0.25,0.25,0.25 ; 0.75,0.75,0.75];

	figure
	set(gcf,'PaperOrientation','landscape','PaperPositionMode','auto');
	% Size to make it look good
	c = get(gcf);
	c.Position(2) = 275;
	c.Position(3) = 870;
	c.Position(4) = 680;
	set(gcf,'Position',c.Position);

	% Find max across directions
	for j = 1:length(s.dir)
		x(j) = max(s.dir(j).histog);
		ymax = max(x)+5;
	end

	% Plot for 2 movements
	for j=1:length(s.dir)
		mvt = s.dir(j);
		left = MARGIN + (WIDTH+MARGIN)*(j-1);
		width = WIDTH;
		height = HEIGHT;      
		bottom = TOP-height;
		subplot('position',[left bottom width height]);

		h=area(bins, mvt.histog);
		set(h,'FaceColor',[0.5,0.5,0.5],'EdgeColor','k');
		xlim([min(bins) max(bins)]);
		ylim([0 ymax]);
		ylm = ylim;
		xlm = xlim;
		hold on
		plot(xlim,[mvt.cntl_mean mvt.cntl_mean],'k-');
		plot(xlim,[mvt.cntl_mean+mvt.sig_thr mvt.cntl_mean+mvt.sig_thr],'k:');
		plot(xlim,[mvt.cntl_mean-mvt.sig_thr mvt.cntl_mean-mvt.sig_thr],'k:');
		plot([0,0],ylm,'k-');
		xlabel('seconds');
		ylabel('spikes/sec');

		if isempty(mvt.chng(1).on_ind)
			text( mean([max(bins) min(bins)]), ylm(2)/2, 'No sig change found',...
					'HorizontalAlignment','center','Color','r');
		else
			for i = 1:2
				chng = mvt.chng(i);

				if ~isempty(bins(chng.on_ind))
					on = bins(chng.on_ind);
					if ~isempty(bins(chng.off_ind))
						off = bins(chng.off_ind);
					else
						off = xlm(2);	%If no offset found, change lasts to end
					end
					x = [ on on off off ];
					y = [ ylm ylm(2:-1:1)];
					fill(x,y,CLR(i,:),'EdgeColor','none','FaceAlpha',0.3)
				end
			end
		end

		
		if j ==1
			str = [ s.fname ':....' s.unitname '....aligned on:' s.align_evt];
			title(str,'Interpreter','none','FontSize',12,...
				'Position',[xlm(2),ylm(2)+5,0]);
		end

		bottom = bottom-height-MARGIN;
		subplot('position',[left bottom width height]);
		rasterplot(mvt.raster,0.9,'');
    end
    
    [p,metafile,x] = fileparts(s.fname);
    metafile = [ metafile '_' strrep(s.unitname,'Channel','') '_' align_select];
    % display(['Saving graphics file:  ' metafile '.emf']);
    print( '-dmeta', '-painters', metafile);
    saveas(h,metafile,'jpg');
    saveas(h,metafile,'fig');
return


%------------------------------------------------------
% Subfunction to write a line of data to output file
function write_text(outfid, spk,N_Pks)
	bins = spk.bins;
	
	fprintf(outfid,'%s\t%s\t', ...
		spk.fname, spk.unitname);

	for j = 1:length(spk.dir)	% mvt directions
		mvt = spk.dir(j);
		fprintf(outfid,'%d\t%.3f\t%.3f\t',...
			 mvt.n_reps, mvt.cntl_mean, mvt.sig_thr );

		for i = 1:N_Pks
			chng = mvt.chng(i);

			% Report significant peaks
			if ~isempty(chng.on_ind)
				fprintf(outfid,'%.3f\t%.3f\t%.3f\t%.3f\t',...
					bins(chng.on_ind),chng.sgn,chng.mean_change,chng.int_change);
			else
				fprintf(outfid,'-\t-\t-\t-\t');
			end
			if ~isempty(chng.off_ind)
				fprintf(outfid,'%.3f\t',bins(chng.off_ind));
			else
				fprintf(outfid,'-\t');
			end
		end
	end
	fprintf(outfid,'\n');
	return

%------------------------------------------------------
% Subfunction to open output file and print header line
function outfid = write_text_header(N_Pks, align_select)
	fname = ['PeriORTask_' align_select '.txt'];
	outfid = fopen(fname,'w');
	if(outfid == -1)
       error(['Unable to open...' fname ]);
	end
	fprintf(outfid,'fname\tunitname\t');
	for j = 1:2
		fprintf(outfid,'Nreps\tcntl_mean\tsig_thresh\t');
		for i = 1:N_Pks
			% For max reported signif acorr pks, freq & normalized power
			fprintf(outfid,'Onset%d\tSign%d\tMeanChange%d\tIntChange%d\tOffset%d\t',i,i,i,i,i);
		end
	end
	fprintf(outfid,'\n');		% EOL

	return

	
