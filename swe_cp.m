function swe_cp(SwE)
 
%-Say hello
%--------------------------------------------------------------------------
Finter = spm('CreateIntWin','off');
set(Finter,'name','SwE estimation');
set(Finter,'vis','on')

%-Get SwE.mat[s] if necessary
%--------------------------------------------------------------------------
if nargin == 0
    P     = cellstr(spm_select(Inf,'^SwE\.mat$','Select SwE.mat[s]'));
    for i = 1:length(P)
        swd     = fileparts(P{i});
        load(fullfile(swd,'SwE.mat'));
        SwE.swd = swd;
        swe_cp(SwE);
    end
    return
end
%-Change to SwE.swd if specified
%--------------------------------------------------------------------------
try
    cd(SwE.swd);
catch %#ok<*CTCH>
    SwE.swd = pwd;
end

%-Ensure data are assigned
%--------------------------------------------------------------------------
try
    SwE.xY.VY;
catch
    spm('alert!','Please assign data to this design', mfilename);
    spm('FigName','Stats: done',Finter); spm('Pointer','Arrow')
    return
end

%-Delete files from previous analyses
%--------------------------------------------------------------------------
if exist(fullfile(SwE.swd,'mask.img'),'file') == 2
 
    str = {'Current directory contains SwE estimation files:',...
        'pwd = ',SwE.swd,...
        'Existing results will be overwritten!'};
    if spm_input(str,1,'bd','stop|continue',[1,0],1)
        spm('FigName','Stats: done',Finter); spm('Pointer','Arrow')
        return
    else
        warning('Overwriting old results\n\t (pwd = %s) ',SwE.swd); %#ok<WNTAG>
        try SwE = rmfield(SwE,'xVol'); end %#ok<TRYNC>
    end
end
 
files = {'^mask\..{3}$','^beta_.{4}\..{3}$','^con_.{4}\..{3}$',...
         '^ResI_.{4}\..{3}$','^cov_beta_.{4}d_.{4}\..{3}$',...
         '^cov_beta_g_.{4}d_.{4}d_.{4}\..{3}$',...
         '^cov_vis_.{4}d_.{4}d_.{4}\..{3}$'
         };
 
for i = 1:length(files)
    j = spm_select('List',SwE.swd,files{i});
    for k = 1:size(j,1)
        spm_unlink(deblank(j(k,:)));
    end
end
 
%==========================================================================
% - A N A L Y S I S   P R E L I M I N A R I E S
%==========================================================================
 
%-Initialise
%==========================================================================
fprintf('%-40s: %30s','Initialising parameters','...computing');        %-#
xX            = SwE.xX;
[nScan nBeta] = size(xX.X);
nCov_beta     = (nBeta+1)*nBeta/2;
pX            = pinv(xX.X); % pseudo-inverse
Hat           = xX.X*(pX); % Hat matrix
iSubj         = SwE.Subj.iSubj;
uSubj         = unique(iSubj);
nSubj         = length(uSubj);

%-residual correction
%
switch SwE.SS   
    case 1
        corr  = sqrt(nScan/(nScan-nBeta)); % residual correction (type 1) 
    case 2
        corr  = (1-diag(Hat)).^(-0.5); % residual correction (type 2)
    case 3
        corr  = (1-diag(Hat)).^(-1); % residual correction (type 3)
end

%-detect if the design matrix is separable (a little bit messy, but seems to do the job)
%
iGr_dof   = zeros(1,nScan);  
iBeta_dof = zeros(1,nBeta);
it = 0;
while ~all(iGr_dof)
    it = it + 1;
    scan = find(iGr_dof==0,1);
    for i = find(iGr_dof==0)
        if any(xX.X(i,:) & xX.X(scan,:))
            iGr_dof(i) = it;
        end
    end
end
%need to check if the partiation is correct
while 1
    uGr_dof = unique(iGr_dof);
    nGr_dof = length(uGr_dof);
    tmp = zeros(nGr_dof,nBeta);
    for i = 1:nGr_dof
        tmp(i,:) = any(xX.X(iGr_dof==i,:));
    end
    if nGr_dof==1 | all(sum(tmp)==1) %#ok<OR2>
        break % all is ok, just stop the while
    else
        ind1 = find(sum(tmp)>1,1); % detect the first column in common
        ind2 = find(tmp(:,ind1)==1); % detect the groups to be fused
        for ii = ind2'
            iGr_dof(iGr_dof==ii) = ind2(1); % fuse the groups 
        end
    end
end
nSubj_dof = zeros(1,nGr_dof); 
for i = 1:nGr_dof % renumber to avoid gaps in the numbering
    iGr_dof(iGr_dof==uGr_dof(i)) = i;
    iBeta_dof(tmp(i,:)==1) = i;
    nSubj_dof(i) = length(unique(iSubj(iGr_dof==uGr_dof(i))));
end
pB_dof   = zeros(1,nGr_dof); 
for i=1:nBeta    
    tmp=1;
    for ii=1:nSubj
        if length(unique(xX.X(iSubj==uSubj(ii),i)))~=1
            tmp=0;
            break
        end
    end
    if tmp == 1
        pB_dof(iBeta_dof(i)) = pB_dof(iBeta_dof(i)) + 1;
    end
end

%-effective dof for each subject
edof_Subj = zeros(1,nSubj);
for i = 1:nSubj
    edof_Subj(i) = 1 - pB_dof(iGr_dof(iSubj==uSubj(i)))/...
        nSubj_dof(iGr_dof(iSubj==uSubj(i)));
end

%-degrees of freedom estimation type
if isfield(SwE.type,'modified')
    dof_type = SwE.type.modified.dof_mo;
else
    dof_type = SwE.type.classic.dof_cl;        
end

if ~dof_type % so naive estimation is used
    dof_cov = zeros(1,nBeta);
    for i = 1:nBeta
        dof_cov(i) = nSubj_dof(iBeta_dof(i)) - ...
            pB_dof(iBeta_dof(i));    
    end;
end

%-preprocessing for the modified SwE
if isfield(SwE.type,'modified')
    iVis      = SwE.Vis.iVis;
    iGr       = SwE.Gr.iGr;
    uGr       = unique(iGr); 
    nGr       = length(uGr);
    
    % info specific for each group
    uVis_g = cell(1,nGr); % unique visits for each group
    nVis_g = zeros(1,nGr); % number of visits for each group
    uSubj_g = cell(1,nGr); % unique visits for each group
    nSubj_g = zeros(1,nGr); % number of visits for each group
    for g = 1:nGr
        uVis_g{g}  = unique(iVis(iGr==uGr(g))); 
        nVis_g(g)  = length(uVis_g{g});
        uSubj_g{g} = unique(iSubj(iGr==uGr(g)));
        nSubj_g(g) = length(uSubj_g{g});
    end
    nCov_vis_g  = nVis_g.*(nVis_g+1)/2; % number of covariance elements to be estimated for each group
    nCov_vis    = sum(nCov_vis_g); % total number of covariance elements to be estimated   
    
    % Flags matrices indicating which residuals have to be used for each covariance element 
    Flagk  = false(nCov_vis,nScan); % Flag indicating scans corresponding to visit k for each covariance element
    Flagkk = false(nCov_vis,nScan); % Flag indicating scans corresponding to visit kk for each covariance element    
    Ind_Cov_vis_diag     = nan(1,sum(nVis_g)); % index of the diagonal elements
    Ind_Cov_vis_off_diag = nan(1,nCov_vis - sum(nVis_g)); % index of the off-diagonal elements
    Ind_corr_diag=nan(nCov_vis,2); % index of the 2 corresponding diagonal elements
    iGr_Cov_vis_g = nan(1,nCov_vis);
    it = 0; it2 = 0; it3 = 0;
    for g = 1:nGr
        for k = 1:nVis_g(g)
            for kk = k:nVis_g(g)
               it = it + 1;               	
               id = intersect(iSubj(iGr==uGr(g) & iVis==uVis_g{g}(k)),...
                   iSubj(iGr==uGr(g) & iVis==uVis_g{g}(kk))); % identifiaction of the subjects with both visits k & kk                
               Flagk(it,:)  = ismember(iSubj,id) & iVis==uVis_g{g}(k);
               Flagkk(it,:) = ismember(iSubj,id) & iVis==uVis_g{g}(kk);              
               if k==kk                 
                   it2 = it2+1;
                   it4 = it2;
                   Ind_Cov_vis_diag(it2)     = it;
               else
                   it3 = it3 + 1;
                   it4 = it4 + 1;
                   Ind_Cov_vis_off_diag(it3) = it;                   
               end
               Ind_corr_diag(it,:) = [it2 it4];
               iGr_Cov_vis_g(it) = g;
            end
        end
    end
    % weights for the vectorised SwE (to be checked)
    weight=NaN(nCov_beta,nCov_vis);
    it=0;
    for j = 1:nBeta
        for jj = j:nBeta
            it=it+1;
            for jjj = Ind_Cov_vis_diag               
                weight(it,jjj) = pX(j,Flagk(jjj,:))*pX(jj,Flagk(jjj,:))';
            end
            for jjj = Ind_Cov_vis_off_diag       
                weight(it,jjj) = pX(j,Flagk(jjj,:))*pX(jj,Flagkk(jjj,:))' + ...
                    pX(j,Flagkk(jjj,:))*pX(jj,Flagk(jjj,:))';              
            end

        end
    end
    %-compute the effective dof from each homogeneous group if dof_type
    if dof_type
        edof_Gr = zeros(1,nGr);
        nSubj_g = zeros(1,nGr);
        for g = 1:nGr
            nSubj_g(g) = length(unique(iSubj(iGr == g)));
            tmp = 0;
            for j = 1:nSubj_g(g)
               tmp = tmp + 1/edof_Subj(uSubj == uSubj_g{g}(j));
            end
            edof_Gr(g) = nSubj_g(g)^2/tmp;
        end
    end
end

%-preprocessing for the classic SwE
if isfield(SwE.type,'classic')
    nVis_i        = zeros(1,nSubj);
    for i = 1:nSubj
        nVis_i(i) = sum(uSubj(i)==iSubj);
    end
    nCov_vis      = sum(nVis_i.*(nVis_i+1)/2); % total number of covariance elements to be estimated   
    weight        = NaN(nCov_beta,nCov_vis);
    Ind_Cov_vis_classic = NaN(1,nCov_vis);
    Indexk  = NaN(1,nCov_vis);
    Indexkk = NaN(1,nCov_vis);
    it = 0;    
    for j = 1:nBeta
        for jj = j:nBeta
            it = it + 1;
            it2 = 0;
            for i = 1:nSubj
                ind_i=find(iSubj == uSubj(i));
                for ii = 1:nVis_i(i)
                    it2 = it2 + 1;
                    weight(it,it2) = pX(j,ind_i(ii))*pX(jj,ind_i(ii));                   
                    Ind_Cov_vis_classic(it2) = i;
                    Indexk(it2)  = ind_i(ii);
                    Indexkk(it2) = ind_i(ii);
                    for iii = (ii+1):nVis_i(i)
                        it2 = it2 + 1;
                        weight(it,it2) = pX(j,ind_i([ii,iii]))*pX(jj,ind_i([iii,ii]))';
                        Ind_Cov_vis_classic(it2) = i;
                        Indexk(it2)  = ind_i(ii);
                        Indexkk(it2) = ind_i(iii);
                    end
                end
            end
        end
    end 
    %-compute the effective dof from each homogeneous group (here, subject)
    if dof_type
       edof_Gr = edof_Subj;
    end
end
%-If xM is not a structure then assume it's a vector of thresholds
%--------------------------------------------------------------------------
try
    xM = SwE.xM;
catch
    xM = -Inf(nScan,1);
end
if ~isstruct(xM)
    xM = struct('T',    [],...
                'TH',   xM,...
                'I',    0,...
                'VM',   {[]},...
                'xs',   struct('Masking','analysis threshold'));
end

%-Image dimensions and data
%==========================================================================
VY       = SwE.xY.VY;
spm_check_orientations(VY);

% check files exists and try pwd
%--------------------------------------------------------------------------
for i = 1:numel(VY)
    if ~spm_existfile(VY(i).fname)
        [p,n,e]     = fileparts(VY(i).fname);
        VY(i).fname = [n,e];
    end
end

M        = VY(1).mat;
DIM      = VY(1).dim(1:3)';
VOX      = sqrt(diag(M(1:3, 1:3)'*M(1:3, 1:3)))';
xdim     = DIM(1); ydim = DIM(2); zdim = DIM(3);
%vFWHM    = SwE.vFWHM; to be added later (for the variance smoothing)
YNaNrep  = spm_type(VY(1).dt(1),'nanrep');

%-Maximum number of residual images for smoothness estimation
%--------------------------------------------------------------------------
MAXRES   = Inf; 
nSres    = nScan;

fprintf('%s%30s\n',repmat(sprintf('\b'),1,30),'...done');               %-#

fprintf('%-40s: %30s','Output images','...initialising');           %-#

%-Initialise new mask name: current mask & conditions on voxels
%----------------------------------------------------------------------
VM    = struct('fname',  'mask.img',...
    'dim',    DIM',...
    'dt',     [spm_type('uint8') spm_platform('bigend')],...
    'mat',    M,...
    'pinfo',  [1 0 0]',...
    'descrip','swe_cp:resultant analysis mask');
VM    = spm_create_vol(VM);

%-Initialise beta image files
%----------------------------------------------------------------------

Vbeta(1:nBeta) = deal(struct(...
    'fname',    [],...
    'dim',      DIM',...
    'dt',       [spm_type('float32') spm_platform('bigend')],...
    'mat',      M,...
    'pinfo',    [1 0 0]',...
    'descrip',  ''));

for i = 1:nBeta
    Vbeta(i).fname   = sprintf('beta_%04d.img',i);
    Vbeta(i).descrip = sprintf('swe_cp:beta (%04d) - %s',i,xX.name{i});
end
Vbeta = spm_create_vol(Vbeta);

%-Initialise Cov_beta image files
%----------------------------------------------------------------------

Vcov_beta(1:nCov_beta) = deal(struct(...
    'fname',    [],...
    'dim',      DIM',...
    'dt',       [spm_type('float32') spm_platform('bigend')],...
    'mat',      M,...
    'pinfo',    [1 0 0]',...
    'descrip',  ''));

it=0;
for i=1:nBeta
    for ii=i:nBeta
        it=it+1;
        Vcov_beta(it).fname= sprintf('cov_beta_%04d_%04d.img',i,ii);
        Vcov_beta(it).descrip=sprintf('cov_beta_%04d_%04d hats - %s/%s',...
            i,ii,xX.name{i},xX.name{ii});
    end
end
Vcov_beta = spm_create_vol(Vcov_beta);

%-Initialise Cov_beta_g image files if needed
%----------------------------------------------------------------------
if dof_type
    if isfield(SwE.type,'classic')
        nGr = nSubj;
    end
    Vcov_beta_g(1:nCov_beta*nGr) = deal(struct(...
        'fname',    [],...
        'dim',      DIM',...
        'dt',       [spm_type('float32') spm_platform('bigend')],...
        'mat',      M,...
        'pinfo',    [1 0 0]',...
        'descrip',  ''));
    
    it=0;
    for g=1:nGr
        for ii=1:nBeta
            for iii=ii:nBeta
                it=it+1;
                Vcov_beta_g(it).fname= sprintf('cov_beta_g_%04d_%04d_%04d.img',g,ii,iii);
                Vcov_beta_g(it).descrip=sprintf('cov_beta_g_%04d_%04d_%04d hats - group %s - %s/%s',...
                    g,ii,iii,num2str(uGr(g)),xX.name{ii},xX.name{iii});
            end
        end
    end
    Vcov_beta_g = spm_create_vol(Vcov_beta_g);
end

%-Initialise cov_vis image files
%----------------------------------------------------------------------
if isfield(SwE.type,'modified')
    Vcov_vis(1:nCov_vis) = deal(struct(...
        'fname',    [],...
        'dim',      DIM',...
        'dt',       [spm_type('float32') spm_platform('bigend')],...
        'mat',      M,...
        'pinfo',    [1 0 0]',...
        'descrip',  ''));
    
    it=0;
    for g =1:nGr
        for ii=1:nVis_g(g)
            for iii=ii:nVis_g(g)
                it=it+1;
                Vcov_vis(it).fname= sprintf('cov_vis_%04d_%04d_%04d.img',g,ii,iii);
                Vcov_vis(it).descrip=sprintf('cov_vis_%04d_%04d_%04d hats - group %s - visits %s/%s',...
                    g,ii,iii,num2str(uGr(g)),num2str(uVis_g{g}(ii)),num2str(uVis_g{g}(iii)));
            end
        end
    end
    Vcov_vis = spm_create_vol(Vcov_vis);
end
%-Initialise standardised residual images
%----------------------------------------------------------------------
VResI(1:nSres) = deal(struct(...
    'fname',    [],...
    'dim',      DIM',...
    'dt',       [spm_type('float32') spm_platform('bigend')],...
    'mat',      M,...
    'pinfo',    [1 0 0]',...
    'descrip',  'swe_cp:StandardisedResiduals'));

for i = 1:nSres
    VResI(i).fname   = sprintf('ResI_%04d.img', i);
    VResI(i).descrip = sprintf('spm_spm:ResI (%04d)', i);
end
VResI = spm_create_vol(VResI);
fprintf('%s%30s\n',repmat(sprintf('\b'),1,30),'...initialised');    %-# 
 
%==========================================================================
% - F I T   M O D E L   &   W R I T E   P A R A M E T E R    I M A G E S
%==========================================================================

%-MAXMEM is the maximum amount of data processed at a time (bytes)
%--------------------------------------------------------------------------
MAXMEM = spm_get_defaults('stats.maxmem');
mmv    = MAXMEM/8/nScan;
blksz  = min(xdim*ydim,ceil(mmv));                             %-block size
nbch   = ceil(xdim*ydim/blksz);                                %-# blocks
nbz    = max(1,min(zdim,floor(mmv/(xdim*ydim)))); nbz = 1;     %-# planes forced to 1 so far
blksz  = blksz * nbz;

%-Initialise variables used in the loop
%==========================================================================
[xords, yords] = ndgrid(1:xdim, 1:ydim);
xords = xords(:)'; yords = yords(:)';           % plane X,Y coordinates
S     = 0;                                      % Volume (voxels)
i_res = round(linspace(1,nScan,nSres))';        % Indices for residual
 
%-Initialise XYZ matrix of in-mask voxel co-ordinates (real space)
%--------------------------------------------------------------------------
XYZ   = zeros(3,xdim*ydim*zdim);

%-Cycle over bunches blocks within planes to avoid memory problems
%==========================================================================
str   = 'parameter estimation';
spm_progress_bar('Init',100,str,'');

for z = 1:nbz:zdim                       %-loop over planes (2D or 3D data)
 
    % current plane-specific parameters
    %----------------------------------------------------------------------
    CrPl         = z:min(z+nbz-1,zdim);       %-plane list
    zords        = CrPl(:)*ones(1,xdim*ydim); %-plane Z coordinates
    CrBl         = [];                        %-parameter estimates
    CrResI       = [];                        %-residuals
    Q            = [];                        %-in mask indices for this plane
    if isfield(SwE.type,'modified')
        CrCov_vis    = []; 
    else
        CrCov_beta   = [];
        if dof_type
            CrCov_beta_i = [];
        end
    end
    
    for bch = 1:nbch                     %-loop over blocks

        %-Print progress information in command window
        %------------------------------------------------------------------
        if numel(CrPl) == 1
            str = sprintf('Plane %3d/%-3d, block %3d/%-3d',...
                z,zdim,bch,nbch);
        else
            str = sprintf('Planes %3d-%-3d/%-3d',z,CrPl(end),zdim);
        end
        if z == 1 && bch == 1
            str2 = '';
        else
            str2 = repmat(sprintf('\b'),1,72);
        end
        fprintf('%s%-40s: %30s',str2,str,' ');


        %-construct list of voxels in this block
        %------------------------------------------------------------------
        I     = (1:blksz) + (bch - 1)*blksz;       %-voxel indices
        I     = I(I <= numel(CrPl)*xdim*ydim);     %-truncate
        xyz   = [repmat(xords,1,numel(CrPl)); ...
            repmat(yords,1,numel(CrPl)); ...
            reshape(zords',1,[])];
        xyz   = xyz(:,I);                          %-voxel coordinates
        nVox  = size(xyz,2);                       %-number of voxels

        %-Get data & construct analysis mask
        %=================================================================
        fprintf('%s%30s',repmat(sprintf('\b'),1,30),'...read & mask data')
        Cm    = true(1,nVox);                      %-current mask

        %-Compute explicit mask
        % (note that these may not have same orientations)
        %------------------------------------------------------------------
        for i = 1:length(xM.VM)

            %-Coordinates in mask image
            %--------------------------------------------------------------
            j = xM.VM(i).mat\M*[xyz;ones(1,nVox)];

            %-Load mask image within current mask & update mask
            %--------------------------------------------------------------
            Cm(Cm) = spm_get_data(xM.VM(i),j(:,Cm),false) > 0;
        end

        %-Get the data in mask, compute threshold & implicit masks
        %------------------------------------------------------------------
        Y     = zeros(nScan,nVox);
        for i = 1:nScan

            %-Load data in mask
            %--------------------------------------------------------------
            if ~any(Cm), break, end                %-Break if empty mask
            Y(i,Cm)  = spm_get_data(VY(i),xyz(:,Cm),false);

            Cm(Cm)   = Y(i,Cm) > xM.TH(i);         %-Threshold (& NaN) mask
            if xM.I && ~YNaNrep && xM.TH(i) < 0    %-Use implicit mask
                Cm(Cm) = abs(Y(i,Cm)) > eps;
            end
        end

        %-Mask out voxels where data is constant in at least one separable
        % matrix design
        %------------------------------------------------------------------
        for g = 1:nGr_dof
            Cm(Cm) = any(diff(Y(iGr_dof==g,Cm),1));
        end
        Y      = Y(:,Cm);                          %-Data within mask
        CrS    = sum(Cm);                          %-# current voxels


        %==================================================================
        %-Proceed with General Linear Model (if there are voxels)
        %==================================================================
        if CrS

            %-General linear model: Ordinary least squares estimation
            %--------------------------------------------------------------
            fprintf('%s%30s',repmat(sprintf('\b'),1,30),'...estimation');%-#

            beta  = pX*Y;                     %-Parameter estimates
            res   = diag(corr)*(Y-xX.X*beta); %-Corrected residuals
            clear Y                           %-Clear to save memory

            %-Estimation of the data variance-covariance components (modified SwE) 
            %-SwE estimation (classic version)
            %--------------------------------------------------------------
            
            if isfield(SwE.type,'modified')
                Cov_beta = 0;
                Cov_vis=zeros(nCov_vis,CrS);
                for i = Ind_Cov_vis_diag
                    Cov_vis(i,:) = mean(res(Flagk(i,:),:).^2);
                end
                for i = Ind_Cov_vis_off_diag
                    Cov_vis(i,:)= sum(res(Flagk(i,:),:).*res(Flagkk(i,:),:)).*...
                        sqrt(Cov_vis(Ind_Cov_vis_diag(Ind_corr_diag(i,1)),:).*...
                        Cov_vis(Ind_Cov_vis_diag(Ind_corr_diag(i,2)),:)./...
                        sum(res(Flagk(i,:),:).^2)./...
                        sum(res(Flagkk(i,:),:).^2));
                end
                %NaN may be produced in cov. estimation when one correspondant
                %variance are = 0, so set them to 0
                Cov_vis(isnan(Cov_vis))=0;
                %need to check if the eigenvalues of Cov_vis matrices are >=0
                for g = 1:nGr
                    for iVox = 1:CrS
                        tmp = zeros(nVis_g(g));                   
                        tmp(tril(ones(nVis_g(g)))==1) = Cov_vis(iGr_Cov_vis_g==g,iVox);
                        tmp = tmp + tmp' - diag(diag(tmp));
                        [V D] = eig(tmp);
                        if any (D<0) 
                            D(D<0) = 0;
                            tmp = V * D * V';
                            Cov_vis(iGr_Cov_vis_g==g,iVox) = tmp(tril(ones(nVis_g))==1);
                        end
                    end
                end
            else
                if dof_type %need to save all subject contributions...
                    Cov_beta_i =  NaN(nSubj,nCov_beta,CrS);
                end
                for i = 1:nSubj
                    Cov_beta_i_tmp = weight(:,Ind_Cov_vis_classic==i) *...
                        (res(Indexk(Ind_Cov_vis_classic==i),:) .* res(Indexkk(Ind_Cov_vis_classic==i),:));
                    Cov_beta = Cov_beta + Cov_beta_i_tmp;
                    if dof_type %need to save all subject contributions...
                        Cov_beta_i(i,:,:) = Cov_beta_i_tmp;
                    end
                end
            end
                
            %-Save betas etc. for current plane as we go along
            %----------------------------------------------------------
            CrBl          = [CrBl,    beta]; %#ok<AGROW>
            CrResI        = [CrResI,  res(i_res,:)]; %#ok<AGROW>
            if isfield(SwE.type,'modified') 
                CrCov_vis     = [CrCov_vis,  Cov_vis]; %#ok<AGROW>
            else
                CrCov_beta     = [CrCov_beta, Cov_beta]; %#ok<AGROW>
                if dof_type
                    CrCov_beta_i     = cat(3, CrCov_beta_i, Cov_beta_i);
                end
            end
        end % (CrS)

        %-Append new inmask voxel locations and volumes
        %------------------------------------------------------------------
        XYZ(:,S + (1:CrS)) = xyz(:,Cm);     %-InMask XYZ voxel coords
        Q                  = [Q I(Cm)];     %#ok<AGROW> %-InMask XYZ voxel indices
        S                  = S + CrS;       %-Volume analysed (voxels)

    end % (bch)

    %-Plane complete, write plane to image files (unless 1st pass)
    %======================================================================

    fprintf('%s%30s',repmat(sprintf('\b'),1,30),'...saving plane'); %-#

    jj = NaN(xdim,ydim,numel(CrPl));

    %-Write Mask image
    %------------------------------------------------------------------
    if ~isempty(Q), jj(Q) = 1; end
    VM    = spm_write_plane(VM, ~isnan(jj), CrPl);

    %-Write beta images
    %------------------------------------------------------------------
    for i = 1:nBeta
        if ~isempty(Q), jj(Q) = CrBl(i,:); end
        Vbeta(i) = spm_write_plane(Vbeta(i), jj, CrPl);
    end

    %-Write visit covariance images
    %------------------------------------------------------------------
    if isfield(SwE.type,'modified')
        for i=1:nCov_vis
            if ~isempty(Q), jj(Q) = CrCov_vis(i,:); end
            Vcov_vis(i) = spm_write_plane(Vcov_vis(i), jj, CrPl);
        end
    end

    %-Write SwE images and contributions if needed
    %------------------------------------------------------------------
    if isfield(SwE.type,'classic')       
        for i=1:nCov_beta
            if ~isempty(Q), jj(Q) = CrCov_beta(i,:); end
            Vcov_beta(i) = spm_write_plane(Vcov_beta(i), jj, CrPl);
        end
        if dof_type
            it = 0;
            for i=1:nSubj
                for ii=1:nCov_beta
                    it = it + 1;
                    if ~isempty(Q), jj(Q) = CrCov_beta_i(i,ii,:); end
                    Vcov_beta_g(it) = spm_write_plane(Vcov_beta_g(it), jj, CrPl);
                end
            end
        end
    end
    
    %-Write standardised residual images
    %------------------------------------------------------------------
    for i = 1:nSres
        if ~isempty(Q), jj(Q) = CrResI(i,:)./...
                sqrt(CrCov_vis(Flagk(:,i) & Flagkk(:,i),:)); 
        end 
        VResI(i) = spm_write_plane(VResI(i), jj, CrPl);
    end

    %-Report progress
    %----------------------------------------------------------------------
    fprintf('%s%30s',repmat(sprintf('\b'),1,30),'...done');   
    spm_progress_bar('Set',100*(bch + nbch*(z - 1))/(nbch*zdim));

end % (for z = 1:zdim)
fprintf('\n');                                                          %-#
spm_progress_bar('Clear')
clear beta res Cov_vis CrBl CrResI CrCov_vis jj%-Clear to save memory
if isfield(SwE.type,'modified')
    clear Cov_vis CrCov_vis
else
    clear  Cov_beta CrCov_beta        
    if dof_type
        clear Cov_beta_i CrCov_beta_i
    end
end
XYZ   = XYZ(:,1:S); % remove all the data not used 

%-SwE computation (for modified version, done later in case of a spatial regul.)
%==========================================================================
if isfield(SwE.type,'modified')
    
    %-Loading the visit covariance for the whole brain
    %----------------------------------------------------------------------
    fprintf('Loading the visit covariance for the SwE computation...'); %-#
    
    Cov_vis = spm_get_data(Vcov_vis,XYZ);
    
    %- Spatial regularization of the visit covariance if required
    %----------------------------------------------------------------------
    % Blurred mask is used to truncate kernel to brain; if not
    % used variance at edges would be underestimated due to
    % convolution with zero activity out side the brain.
    %-----------------------------------------------------------------
%     Q           = cumprod([1,DIM(1:2)'])*XYZ - ...
%         sum(cumprod(DIM(1:2)'));
%     if ~all(vFWHM==0)
%         fprintf('Working on the SwE spatial regularization...'); %-#
%         SmCov_vis = zeros(xdim, ydim, zdim);
%         SmMask    = zeros(xdim, ydim, zdim);
%         TmpVol    = zeros(xdim, ydim, zdim);
%         TmpVol(Q) = ones(size(Q));
%         spm_smooth(TmpVol,SmMask,vFWHM./VOX);
%         jj = NaN(xdim,ydim,zdim);
%         for i = 1:nCov_vis
%             TmpVol(Q) = Cov_vis(i,:);
%             spm_smooth(TmpVol,SmCov_vis,vFWHM./VOX);
%             Cov_vis (i,:) = SmCov_vis(Q)./SmMask(Q);
%             jj(Q) = Cov_vis (i,:);
%             spm_write_vol(Vsmcov_vis(i),jj);
%         end
%     end
    fprintf('\n');                                                    %-#
    disp('Working on the SwE computation...');
    %Computation of the SwE
    str   = 'SwE computation';
    spm_progress_bar('Init',100,str,'');
    
    S_z = 0;
    jj = NaN(xdim,ydim);
    for z = 1:zdim                       %-loop over planes (2D or 3D data)       
        XY_z = XYZ(1:2,XYZ(3,:)==z); % extract coord in plane z        
        Q_z = cumprod([1,DIM(1)'])*XY_z - ...
            sum(cumprod(DIM(1)'));
        s_z = length(XY_z); % number of active voxels in plane z
        if dof_type
            Cov_beta = zeros(nCov_beta,s_z); % initialize SwE for the plane
            it = 0;
            for g = 1:nGr
                Cov_beta_g = weight(:,iGr_Cov_vis_g==g) * Cov_vis(iGr_Cov_vis_g==g,(1+S_z):(S_z+s_z));
                for i=1:nCov_beta
                    if ~isempty(Q_z), jj(Q_z)=Cov_beta_g(i,:); end
                    it = it + 1;
                    Vcov_beta_g(it)=spm_write_plane(Vcov_beta_g(it),jj, z);
                end
                Cov_beta = Cov_beta + Cov_beta_g;
                spm_progress_bar('Set',100*((z-1)/zdim + g/nGr/zdim));
            end
        else
            Cov_beta = weight * Cov_vis(:,(1+S_z):(S_z+s_z));
            spm_progress_bar('Set',100*(z/zdim));
        end
        for i=1:nCov_beta
            if ~isempty(Q_z), jj(Q_z)=Cov_beta(i,:); end
            Vcov_beta(i)=spm_write_plane(Vcov_beta(i),jj, z);
        end
        S_z = S_z + s_z;
    end% (for z = 1:zdim)
    fprintf('\n');                                                    %-#
    spm_progress_bar('Clear')
    
end


%==========================================================================
% - P O S T   E S T I M A T I O N   C L E A N U P
%==========================================================================
if S == 0, spm('alert!','No inmask voxels - empty analysis!'); return; end


%-Smoothness estimates of component fields and RESEL counts for volume
%==========================================================================
try
    FWHM = SwE.xVol.FWHM;
    VRpv = SwE.xVol.VRpv;
    R    = SwE.xVol.R;
catch
    erdf      = spm_SpUtil('trRV',xX.X); % Working error df / do not agree to be checked
    [FWHM,VRpv,R] = spm_est_smoothness(VResI,VM,[nScan erdf]);
end

%-Delete the residuals images
%==========================================================================
j = spm_select('List',SwE.swd,'^ResI_.{4}\..{3}$');
for  k = 1:size(j,1)
    spm_unlink(deblank(j(k,:)));
end

%-Compute scaled design matrix for display purposes
%--------------------------------------------------------------------------
%xX.nX        = spm_DesMtx('sca',xX,xX.name);

%-Save remaining results files and analysis parameters
%==========================================================================
fprintf('%-40s: %30s','Saving results','...writing');

%-place fields in SwE
%--------------------------------------------------------------------------
SwE.xVol.XYZ   = XYZ;               %-InMask XYZ coords (voxels)
SwE.xVol.M     = M;                 %-voxels -> mm
SwE.xVol.iM    = inv(M);            %-mm -> voxels
SwE.xVol.DIM   = DIM;               %-image dimensions
SwE.xVol.FWHM  = FWHM;              %-Smoothness data
SwE.xVol.R     = R;                 %-Resel counts
SwE.xVol.S     = S;                 %-Volume (voxels)
SwE.xVol.VRpv  = VRpv;              %-Filehandle - Resels per voxel
SwE.xVol.units = {'mm' 'mm' 'mm'};

SwE.Vbeta      = Vbeta;             %-Filehandle - Beta
SwE.Vcov_beta  = Vcov_beta;         %-Filehandle - Beta covariance
if isfield(SwE.type,'modified')
    SwE.Vcov_vis   = Vcov_vis;      %-Filehandle - Visit covariance    
end
if dof_type
    SwE.Vcov_beta_g  = Vcov_beta_g;     %-Filehandle - Beta covariance contributions
end
% if ~all(vFWHM==0)
%     SwE.Vsmcov_vis = Vsmcov_vis;    %-Filehandle - Visit covariance
% end
SwE.VM         = VM;                %-Filehandle - Mask

SwE.xX         = xX;                %-design structure
SwE.xM         = xM;                %-mask structure

SwE.xCon       = struct([]);        %-contrast structure

SwE.swd        = pwd;

SwE.Subj.uSubj = uSubj;
SwE.Subj.nSubj = nSubj;

if isfield(SwE.type,'modified')
    
    SwE.Vis.uVis_g = uVis_g;
    SwE.Vis.nVis_g = nVis_g;
    SwE.Vis.nCov_vis_g = nCov_vis_g;
    SwE.Vis.nCov_vis = nCov_vis;
    
    SwE.Gr.uGr       = uGr;
    SwE.Gr.nGr       = nGr;
    SwE.Gr.nSubj_g   = nSubj_g;
    SwE.Gr.uSubj_g   = uSubj_g;
else
    if dof_type
        SwE.Gr.nGr   = nSubj;
    end
end

SwE.dof.uGr_dof   = uGr_dof; 
SwE.dof.nGr_dof   = nGr_dof;
SwE.dof.iGr_dof   = iGr_dof; 
SwE.dof.iBeta_dof = iBeta_dof;
SwE.dof.pB_dof    = pB_dof;
SwE.dof.nSubj_dof = nSubj_dof;
SwE.dof.edof_Subj = edof_Subj;
SwE.dof.dof_type  = dof_type;
if dof_type % so naive estimation is used
    SwE.dof.edof_Gr = edof_Gr;
else
    SwE.dof.dof_cov = dof_cov;
end

%-Save analysis parameters in SwE.mat file
%--------------------------------------------------------------------------
if spm_matlab_version_chk('7') >=0
    save('SwE','SwE','-V6');
else
    save('SwE','SwE');
end

%==========================================================================
%- E N D: Cleanup GUI
%==========================================================================
fprintf('%s%30s\n',repmat(sprintf('\b'),1,30),'...done')                %-#
%spm('FigName','Stats: done',Finter); spm('Pointer','Arrow')
fprintf('%-40s: %30s\n','Completed',spm('time'))                        %-#
fprintf('...use the results section for assessment\n\n')  
