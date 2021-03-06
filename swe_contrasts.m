function [SwE] = swe_contrasts(SwE,Ic)
% Fills in SwE.xCon and writes con_????.img, ess_????.img and SwE?_????.img
% FORMAT [SwE] = SwE_contrasts(SwE,Ic)
%
% SwE - SwE data structure
% Ic  - indices of xCon to compute
% Modified version of spm_contrasts adapted for the SwE toolbox
% By Bryan Guillaume

% Temporary SwE variable to check for any changes to SwE. We want to avoid
% always having to save SwE.mat unless it has changed, because this is
% slow. A side benefit is one can look at results with just read
% privileges.
%--------------------------------------------------------------------------
tmpSwE = SwE;

%-Get and change to results directory
%--------------------------------------------------------------------------
try
    cd(SwE.swd);
end

%-Get contrast definitions (if available)
%--------------------------------------------------------------------------
try
    xCon = SwE.xCon;
catch
    xCon = [];
end

%-Set all contrasts by default
%--------------------------------------------------------------------------
if nargin < 2
    Ic   = 1:length(xCon);
end

%-Map parameter files
%--------------------------------------------------------------------------
    
%-OLS estimators and covariance estimates
%--------------------------------------------------------------------------
Vbeta = SwE.Vbeta;
Vcov_beta = SwE.Vcov_beta;
dof_type = SwE.dof.dof_type;
if dof_type == 1
    Vcov_beta_g = SwE.Vcov_beta_g;
end
if dof_type>1
    Vcov_vis = SwE.Vcov_vis;
end

%-Compute & store contrast parameters, contrast/ESS images, & SwE images
%==========================================================================
spm('Pointer','Watch')
XYZ   = SwE.xVol.XYZ;
S=size(XYZ,2);
for i = 1:length(Ic)
     
    %-Canonicalise contrast structure with required fields
    %----------------------------------------------------------------------
    ic = Ic(i);
    %-Write contrast images?
    %======================================================================
    if isempty(xCon(ic).Vspm)
        Q = cumprod([1,SwE.xVol.DIM(1:2)'])*XYZ - ...
            sum(cumprod(SwE.xVol.DIM(1:2)'));
        Co=xCon(ic).c;
        nBeta = size(Co,1);
        nSizeCon = size(Co,2);
        xCon(ic).eidf=rank(Co);
        % detect the indices of the betas of interest
        if nSizeCon==1
            ind = find(Co ~= 0);
        else
            ind = find(any(Co'~=0));
        end
        nCov_beta = (nBeta+1)*nBeta/2;

        % if the Co is a vector, then create Co * Beta (Vcon)
        if nSizeCon==1
            %-Compute contrast
            %------------------------------------------------------
            fprintf('\t%-32s: %30s',sprintf('contrast image %2d',ic),...
                '...computing');                                %-#
            str   = 'contrast computation';
            spm_progress_bar('Init',100,str,'');            
            V      = Vbeta(ind);
            cB     = zeros(1,S);
            for j=1:numel(V)
                cB = cB + Co(ind(j)) * spm_get_data(V(j),XYZ);
                spm_progress_bar('Set',100*(j/numel(V)));
            end
            spm_progress_bar('Clear')            
            %-Prepare handle for contrast image
            %------------------------------------------------------
            xCon(ic).Vcon = struct(...
                'fname',  sprintf('con_%04d.img',ic),...
                'dim',    SwE.xVol.DIM',...
                'dt',     [spm_type('float32') spm_platform('bigend')],...
                'mat',    SwE.xVol.M,...
                'pinfo',  [1,0,0]',...
                'descrip',sprintf('SwE contrast - %d: %s',ic,xCon(ic).name));
            
            %-Write image
            %------------------------------------------------------
            tmp = NaN(SwE.xVol.DIM');
            tmp(Q) = cB;            
            xCon(ic).Vcon = spm_write_vol(xCon(ic).Vcon,tmp);
                    
            clear tmp
            fprintf('%s%30s\n',repmat(sprintf('\b'),1,30),sprintf(...
                        '...written %s',spm_file(xCon(ic).Vcon.fname,'filename')))%-#

        else
            %-Compute contrast
            %------------------------------------------------------
            fprintf('\t%-32s: %30s',sprintf('contrast image %2d',ic),...
                '...computing');                                %-#
            str   = 'contrast computation';
            spm_progress_bar('Init',100,str,'');
            V      = Vbeta(ind);
            cB     = zeros(nSizeCon,S);
            for j=1:numel(V)
                cB = cB + Co(ind(j),:)' * spm_get_data(V(j),XYZ);
                spm_progress_bar('Set',100*(j/numel(V)));
            end 
            spm_progress_bar('Clear')
        end
        
        
        %-Write inference SwE
        %======================================================================
        
        %-compute the contrasted beta covariances and edof for the contrast
        fprintf('\t%-32s: %30s',sprintf('spm{%c} image %2d',xCon(ic).STAT,ic),...
            '...computing');                                %-#
        str   = 'contrasted beta covariance computation';
        spm_progress_bar('Init',100,str,'');            

        it = 0;
        it2 = 0;
        cCovBc = zeros(nSizeCon*(nSizeCon+1)/2,S);
        if dof_type == 1
            cCovBc_g = zeros(nSizeCon*(nSizeCon+1)/2,S,SwE.Gr.nGr);
        else
            xCon(ic).edf = sum(SwE.dof.nSubj_dof(unique(SwE.dof.iBeta_dof(ind))) - ...
            SwE.dof.pB_dof(unique(SwE.dof.iBeta_dof(ind)))); 
        end
        for j = 1:nBeta
            for jj = j:nBeta
                it = it + 1;
                if any(j == ind) && any(jj == ind)
                    it2 = it2+1;
                    weight = Co(j,:)'*Co(jj,:);
                    if (j~=jj) %was wrong (BG - 13/09/13) 
                        weight = weight + weight';
                    end
                    weight = weight(tril(ones(nSizeCon))==1);
                    cCovBc = cCovBc + weight * spm_get_data(Vcov_beta(it),XYZ);
                    if dof_type == 1
                        for g = 1:SwE.Gr.nGr                            
                            cCovBc_g(:,:,g) = cCovBc_g(:,:,g) + weight *...
                                spm_get_data(Vcov_beta_g((g-1)*nCov_beta+it),XYZ);
                            spm_progress_bar('Set',100*((it2-1+g/SwE.Gr.nGr)/length(ind)/(length(ind)+1)*2));
                        end
                    end
                    spm_progress_bar('Set',100*(it2/length(ind)/(length(ind)+1)*2));
                end
            end
        end
        spm_progress_bar('Clear')

        str   = 'spm computation';
        spm_progress_bar('Init',100,str,'');
        Z2 = zeros(1,S);
        switch(xCon(ic).STAT)
            case 'T'                                 %-Compute spm{t} image
                %----------------------------------------------------------
                eSTAT = 'Z';
                Z = cB ./ sqrt(cCovBc);
                spm_progress_bar('Set',100*(0.1));
                switch dof_type 
                    case 1
                        tmp = 0;
                        for g = 1:SwE.Gr.nGr
                            tmp = tmp + cCovBc_g(:,:,g).^2/SwE.dof.edof_Gr(g);
                            spm_progress_bar('Set',100*(g/SwE.Gr.nGr/10+0.1));
                        end
                        clear cCovBc_g
                        edf = cCovBc.^2 ./ tmp;
                        spm_progress_bar('Set',100*(0.2));
                        % transform into Z-scores image
                        if any(Z>0) % avoid to run the following line when all Z are < 0 (BG - 22/08/2016)
                          Z2(Z>0) = -swe_invNcdf(spm_Tcdf(-Z(Z>0),edf(Z>0))); 
                        end
                        if any(Z<0) % avoid to run the following line when all Z are > 0(BG - 22/08/2016)
                         Z2(Z<0) = swe_invNcdf(spm_Tcdf(Z(Z<0),edf(Z<0))); 
                        end
                        %Z = -log10(1-spm_Tcdf(Z,edf)); %transfo into -log10(p)
                        spm_progress_bar('Set',100);
                    case 0
                        % transform into Z-scores image
                        if any(Z>0) % avoid to run the following line when all Z are < 0 (BG - 22/08/2016)
                          Z2(Z>0) = -swe_invNcdf(spm_Tcdf(-Z(Z>0),xCon(ic).edf)); 
                        end
                        if any(Z<0) % avoid to run the following line when all Z are > 0(BG - 22/08/2016)
                          Z2(Z<0) = swe_invNcdf(spm_Tcdf(Z(Z<0),xCon(ic).edf));
                        end
                        % transform into -log10(p-values) image
                        %Z = -log10(1-spm_Tcdf(Z,xCon(ic).edf));
                        spm_progress_bar('Set',100);
                    case 2
                        CovcCovBc = 0;
                        for g = 1:SwE.Gr.nGr
                            Wg = kron(Co,Co)' * swe_duplication_matrix(nBeta) * SwE.Vis.weight(:,SwE.Vis.iGr_Cov_vis_g==g);
                            Wg = kron(Wg,Wg) * swe_duplication_matrix(SwE.Vis.nCov_vis_g(g));
                            CovcCovBc = CovcCovBc + Wg * swe_vechCovVechV(spm_get_data(Vcov_vis(SwE.Vis.iGr_Cov_vis_g==g),XYZ),SwE.dof.dofMat{g},1);
                            spm_progress_bar('Set',100*(0.1) + g*80/SwE.Gr.nGr);
                        end
                        clear Wg
                        edf = 2 * cCovBc.^2 ./ CovcCovBc - 2; 
                        clear CovcCovBc
                        % transform into Z-scores image
                        if any(Z>0) % avoid to run the following line when all Z are < 0 (BG - 22/08/2016)
                          Z2(Z>0) = -swe_invNcdf(spm_Tcdf(-Z(Z>0),edf(Z>0))); 
                        end
                        if any(Z<0) % avoid to run the following line when all Z are > 0(BG - 22/08/2016)
                          Z2(Z<0) = swe_invNcdf(spm_Tcdf(Z(Z<0),edf(Z<0)));
                        end
                        %Z = -log10(1-spm_Tcdf(Z,edf)); %transfo into -log10(p)
                        spm_progress_bar('Set',100);
                    case 3
                        CovcCovBc = 0;
                        for g = 1:SwE.Gr.nGr
                            Wg = kron(Co,Co)' * swe_duplication_matrix(nBeta) * SwE.Vis.weight(:,SwE.Vis.iGr_Cov_vis_g==g);
                            Wg = kron(Wg,Wg) * swe_duplication_matrix(SwE.Vis.nCov_vis_g(g));
                            CovcCovBc = CovcCovBc + Wg * swe_vechCovVechV(spm_get_data(Vcov_vis(SwE.Vis.iGr_Cov_vis_g==g),XYZ),SwE.dof.dofMat{g},2);
                            spm_progress_bar('Set',100*(0.1) + g*80/SwE.Gr.nGr);                            
                        end  
                        clear Wg
                        edf = 2 * cCovBc.^2 ./ CovcCovBc;
                        clear CovcCovBc
                        % transform into Z-scores image
                        if any(Z>0) % avoid to run the following line when all Z are < 0 (BG - 22/08/2016)
                          Z2(Z>0) = -swe_invNcdf(spm_Tcdf(-Z(Z>0),edf(Z>0))); 
                        end
                        if any(Z<0) % avoid to run the following line when all Z are > 0(BG - 22/08/2016)
                          Z2(Z<0) = swe_invNcdf(spm_Tcdf(Z(Z<0),edf(Z<0)));
                        end
                        %Z = -log10(1-spm_Tcdf(Z,edf)); %transfo into -log10(p)
                        spm_progress_bar('Set',100);
                end               
                
            case 'F'                                 %-Compute spm{F} image
                %---------------------------------------------------------
                eSTAT = 'X';
                if nSizeCon==1
                    Z = abs(cB ./ sqrt(cCovBc));
                    spm_progress_bar('Set',100*(0.1));
                    switch dof_type
                        case 1
                            tmp = 0;
                            for g = 1:SwE.Gr.nGr
                                tmp = tmp + cCovBc_g(:,:,g).^2/SwE.dof.edof_Gr(g);
                                spm_progress_bar('Set',100*(g/SwE.Gr.nGr/10+0.1));
                            end
                            clear cCovBc_g
                            edf = cCovBc.^2 ./ tmp;
                            spm_progress_bar('Set',100*(3/4));
                            % transform into X-scores image 
                            Z2 = (swe_invNcdf(spm_Tcdf(-abs(Z),edf))).^2;
                            % transform into -log10(p-values) image
                            %Z = -log10(1-spm_Fcdf(Z,1,edf));
                            spm_progress_bar('Set',100);
                        case 0
                            % transform into X-scores image
                            Z2 = (swe_invNcdf(spm_Tcdf(-abs(Z),xCon(ic).edf))).^2;
                            % transform into -log10(p-values) image
                            %Z = -log10(1-spm_Fcdf(Z,1, xCon(ic).edf));
                            spm_progress_bar('Set',100);
                        case 2
                            CovcCovBc = 0;
                            for g = 1:SwE.Gr.nGr
                                Wg = kron(Co,Co)' * swe_duplication_matrix(nBeta) * SwE.Vis.weight(:,SwE.Vis.iGr_Cov_vis_g==g);
                                Wg = kron(Wg,Wg) * swe_duplication_matrix(SwE.Vis.nCov_vis_g(g));
                                CovcCovBc = CovcCovBc + Wg * swe_vechCovVechV(spm_get_data(Vcov_vis(SwE.Vis.iGr_Cov_vis_g==g),XYZ),SwE.dof.dofMat{g},1);
                                spm_progress_bar('Set',100*(g/SwE.Gr.nGr/10+0.1));
                            end
                            clear Wg
                            edf = 2 * cCovBc.^2 ./ CovcCovBc - 2; 
                            clear CovcCovBc
                            spm_progress_bar('Set',100*(3/4));
                            % transform into X-scores image
                            Z2 = (swe_invNcdf(spm_Tcdf(-abs(Z),edf))).^2;
                            % transform into -log10(p-values) image
                            %Z = -log10(1-spm_Fcdf(Z,1,edf));
                            spm_progress_bar('Set',100);
                        case 3
                            CovcCovBc = 0;
                            for g = 1:SwE.Gr.nGr
                                Wg = kron(Co,Co)' * swe_duplication_matrix(nBeta) * SwE.Vis.weight(:,SwE.Vis.iGr_Cov_vis_g==g);
                                Wg = kron(Wg,Wg) * swe_duplication_matrix(SwE.Vis.nCov_vis_g(g));
                                CovcCovBc = CovcCovBc + Wg * swe_vechCovVechV(spm_get_data(Vcov_vis(SwE.Vis.iGr_Cov_vis_g==g),XYZ),SwE.dof.dofMat{g},2);
                                spm_progress_bar('Set',100*(g/SwE.Gr.nGr/10+0.1));                           
                            end  
                            clear Wg
                            edf = 2 * cCovBc.^2 ./ CovcCovBc;
                            % transform into X-scores image
                            Z2 = (swe_invNcdf(spm_Tcdf(-abs(Z),edf))).^2;
                            % transform into -log10(p-values) image
                            %Z = -log10(1-spm_Fcdf(Z,1,edf));
                            spm_progress_bar('Set',100);
                            clear CovcCovBc
                    end
                    % need to transform in F-score, not in absolute t-score
                    % corrected on 12/05/15 by BG
                    Z = Z.^2;
                    
                else
                    Z   = zeros(1,S);
                    if dof_type ~= 0
                        edf = zeros(1,S);
                    end
                    if dof_type == 2
                        CovcCovBc = 0;
                        for g = 1:SwE.Gr.nGr
                             Wg = kron(Co,Co)' * swe_duplication_matrix(nBeta) * SwE.Vis.weight(:,SwE.Vis.iGr_Cov_vis_g==g);
                             Wg = sum(kron(Wg,Wg)) * swe_duplication_matrix(SwE.Vis.nCov_vis_g(g));
                             CovcCovBc = CovcCovBc + Wg * swe_vechCovVechV(spm_get_data(Vcov_vis(SwE.Vis.iGr_Cov_vis_g==g),XYZ),SwE.dof.dofMat{g},1);
                        end
                        edf = 2 * (sum(swe_duplication_matrix(nSizeCon)) * cCovBc).^2 ./ CovcCovBc - 2;
                    end
                    if dof_type == 3
                      CovcCovBc = 0;
                      tmp = eye(nSizeCon^2);
                      for g = 1:SwE.Gr.nGr
                        Wg = kron(Co,Co)' * swe_duplication_matrix(nBeta) * SwE.Vis.weight(:,SwE.Vis.iGr_Cov_vis_g==g);
                        % tmp is used to sum only the diagonal element
                        % this is useful to compute the trace as
                        % tr(A) = vec(I)' * vec(A)
                        Wg = tmp(:)' * (kron(Wg,Wg)) * swe_duplication_matrix(SwE.Vis.nCov_vis_g(g));
                        CovcCovBc = CovcCovBc + Wg * swe_vechCovVechV(spm_get_data(Vcov_vis(SwE.Vis.iGr_Cov_vis_g==g),XYZ),SwE.dof.dofMat{g},2);
                      end
                      % note that tr(A^2) = vec(A)' * vec(A)
                      tmp = eye(nSizeCon);
                      edf = (sum(swe_duplication_matrix(nSizeCon)) * cCovBc.^2 +...
                        (tmp(:)' * swe_duplication_matrix(nSizeCon) * cCovBc).^2) ./ CovcCovBc;
                    end
                    % define a parameter to tell when to update progress
                    % bar only 80 times
                    updateEvery = round(S/80);
                    for iVox=1:S
                        cCovBc_vox = zeros(nSizeCon);
                        cCovBc_vox(tril(ones(nSizeCon))==1) = cCovBc(:,iVox);
                        cCovBc_vox = cCovBc_vox + cCovBc_vox' - diag(diag(cCovBc_vox));
                        Z(iVox) = cB(:,iVox)' / cCovBc_vox * cB(:,iVox);                   
                        if (dof_type == 1)					   
                          tmp = 0;
                          for g = 1:SwE.Gr.nGr
                            cCovBc_g_vox = zeros(nSizeCon);
                            cCovBc_g_vox(tril(ones(nSizeCon))==1) = cCovBc_g(:,iVox,g);
                            cCovBc_g_vox = cCovBc_g_vox + cCovBc_g_vox' - diag(diag(cCovBc_g_vox));
                            tmp = tmp + (trace(cCovBc_g_vox^2) + (trace(cCovBc_g_vox))^2)/...
                              SwE.dof.edof_Gr(g);                              
                          end
                          edf(iVox)=(trace(cCovBc_vox^2) + (trace(cCovBc_vox))^2) / tmp;                            
                        end
                        % update progress_bar only approx 80 times 
                        if (mod(iVox,updateEvery) == 0)
                          spm_progress_bar('Set',10 + 80 * (iVox/S));
                        end
                    end
                    if dof_type ~= 0
                        clear cCovBc_g
                        Z = Z .*(edf-xCon(ic).eidf+1)./edf/xCon(ic).eidf;
                        Z(Z < 0) = 0; % force negatif F-score to 0 (can happen for very low edf) 
                        % transform into X-scores image
                        % Z2 = chi2inv(spm_Fcdf(Z,xCon(ic).eidf,edf-xCon(ic).eidf+1),1);
                        try % check if the user do not have the fcdf function or one with 'upper' option
                          Z2(Z>1) = swe_invNcdf(fcdf(Z(Z>1),xCon(ic).eidf,edf(Z>1)-xCon(ic).eidf+1,'upper')/2).^2; % more accurate to look this way for high scores
                          Z2(Z<=1 & Z > 0) = swe_invNcdf(0.5 - fcdf(Z(Z<=1 & Z > 0),xCon(ic).eidf,edf(Z<=1 & Z > 0)-xCon(ic).eidf+1)/2).^2;
                        catch 
                          Z2(Z>0) = swe_invNcdf(betainc((edf(Z>0) - xCon(ic).eidf + 1)./(edf(Z>0) - xCon(ic).eidf + 1 + xCon(ic).eidf * Z(Z>0)),(edf(Z>0)-xCon(ic).eidf+1)/2, xCon(ic).eidf/2)/2).^2; 
%                             Z2 = swe_invNcdf(0.5 - spm_Fcdf(Z,xCon(ic).eidf, edf-xCon(ic).eidf+1)/2).^2;
                        end
                        Z2(Z == 0) = 0;
                        % transform into -log10(p-values) image
                        %Z = -log10(1-spm_Fcdf(Z,xCon(ic).eidf,edf));
                    else
                        Z = Z *(xCon(ic).edf -xCon(ic).eidf+1)/xCon(ic).edf/xCon(ic).eidf;
                        Z(Z < 0) = 0; % force negatif F-score to 0 (can happen for very low edf) 
                        % transform into X-scores image
                        %Z2 = chi2inv(spm_Fcdf(Z,xCon(ic).eidf,xCon(ic).edf-xCon(ic).eidf+1),1);
                        try % check if the user do not have the fcdf function or one with 'upper' options
                          Z2(Z>1) = swe_invNcdf(fcdf(Z(Z>1),xCon(ic).eidf,xCon(ic).edf-xCon(ic).eidf+1,'upper')/2).^2; % more accurate to look this way for high score
                          Z2(Z<=1 & Z > 0) = swe_invNcdf(0.5 - fcdf(Z(Z<=1 & Z > 0),xCon(ic).eidf,xCon(ic).edf-xCon(ic).eidf+1)/2).^2;
                        catch 
                          Z2(Z>0) = swe_invNcdf(betainc((xCon(ic).edf - xCon(ic).eidf + 1)./(xCon(ic).edf - xCon(ic).eidf + 1 + xCon(ic).eidf * Z(Z>0)),(xCon(ic).edf-xCon(ic).eidf+1)/2, xCon(ic).eidf/2)/2).^2; 
%                           Z2(Z>0) = swe_invNcdf(0.5 - spm_Fcdf(Z,xCon(ic).eidf,xCon(ic).edf-xCon(ic).eidf+1)/2).^2;
                        end
                        Z2(Z == 0) = 0;
                        % transform into -log10(p-values) image
                        %Z = -log10(1-spm_Fcdf(Z,xCon(ic).eidf,xCon(ic).edf));
                    end
                    spm_progress_bar('Set',100);
                end
        end
        spm_progress_bar('Clear')
        clear cCovBc cB tmp
        
        
        %-Write SwE - statistic images & edf image if needed
        %------------------------------------------------------------------
        fprintf('%s%30s',repmat(sprintf('\b'),1,30),'...writing');      %-#

        xCon(ic).Vspm = struct(...
            'fname',  sprintf('spm%c_%04d.img',eSTAT,ic),...
            'dim',    SwE.xVol.DIM',...
            'dt',     [spm_type('float32'), spm_platform('bigend')],...
            'mat',    SwE.xVol.M,...
            'pinfo',  [1,0,0]',...
            'descrip',sprintf('spm{%c} - contrast %d: %s',...%'SwE{%c_%s} - contrast %d: %s'
           eSTAT,ic,xCon(ic).name));% eSTAT,str,ic,xCon(ic).name));
        xCon(ic).Vspm = spm_create_vol(xCon(ic).Vspm);
        
        Z2 (Z2 > realmax('single')) = realmax('single');
        Z2 (Z2 < -realmax('single')) = -realmax('single');
        
        tmp           = zeros(SwE.xVol.DIM');
        tmp(Q)        = Z2;
        xCon(ic).Vspm = spm_write_vol(xCon(ic).Vspm,tmp);

        clear tmp Z2
        fprintf('%s%30s\n',repmat(sprintf('\b'),1,30),sprintf(...
            '...written %s',spm_str_manip(xCon(ic).Vspm.fname,'t')));
        %-# 
        fprintf('%s%30s',repmat(sprintf('\b'),1,30),'...writing');      %-#

        xCon(ic).Vspm2 = struct(...
            'fname',  sprintf('spm%c_%04d.img',xCon(ic).STAT,ic),...
            'dim',    SwE.xVol.DIM',...
            'dt',     [spm_type('float32'), spm_platform('bigend')],...
            'mat',    SwE.xVol.M,...
            'pinfo',  [1,0,0]',...
            'descrip',sprintf('spm{%c} - contrast %d: %s',...%'SwE{%c_%s} - contrast %d: %s'
           xCon(ic).STAT,ic,xCon(ic).name));% xCon(ic).STAT,str,ic,xCon(ic).name));
        xCon(ic).Vspm2 = spm_create_vol(xCon(ic).Vspm2);

        tmp           = zeros(SwE.xVol.DIM');
        tmp(Q)        = Z;
        xCon(ic).Vspm2 = spm_write_vol(xCon(ic).Vspm2,tmp);

        clear tmp Z
        fprintf('%s%30s\n',repmat(sprintf('\b'),1,30),sprintf(...
            '...written %s',spm_str_manip(xCon(ic).Vspm2.fname,'t')));   %-#

     
        
        if dof_type
            xCon(ic).Vedf = struct(...
                'fname',  sprintf('edf_%04d.img',ic),...
                'dim',    SwE.xVol.DIM',...
                'dt',     [16 spm_platform('bigend')],...
                'mat',    SwE.xVol.M,...
                'pinfo',  [1,0,0]',...
                'descrip',sprintf('SwE effective degrees of freedom - %d: %s',ic,xCon(ic).name));
            fprintf('%s%20s',repmat(sprintf('\b'),1,20),'...computing')%-#
            xCon(ic).Vedf = spm_create_vol(xCon(ic).Vedf);
            tmp = NaN(SwE.xVol.DIM');
            tmp(Q) = edf;
            xCon(ic).Vedf = spm_write_vol(xCon(ic).Vedf,tmp);
            
            clear tmp edf
            fprintf('%s%30s\n',repmat(sprintf('\b'),1,30),sprintf(...
                '...written %s',spm_str_manip(xCon(ic).Vedf.fname,'t')))%-#
              
        end
                           
    end % if isempty(xCon(ic).Vspm)

end % (for i = 1:length(Ic))
spm('Pointer','Arrow')

% place xCon back in SwE
%--------------------------------------------------------------------------
SwE.xCon = xCon;

% Check if SwE has changed. Save only if it has.
%--------------------------------------------------------------------------
if ~isequal(tmpSwE,SwE)
    if spm_matlab_version_chk('7') >=0
        save('SwE', 'SwE', '-V6');
    else
        save('SwE', 'SwE');
    end
end
