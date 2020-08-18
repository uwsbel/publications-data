% =============================================================================
  % SIMULATION-BASED ENGINEERING LAB (SBEL) - http://sbel.wisc.edu
  %
  % Copyright (c) 2019 SBEL
  % All rights reserved.
  %
  % Use of this source code is governed by a BSD-style license that can be found
  % at https://opensource.org/licenses/BSD-3-Clause
  %
  % =============================================================================
  % Contributors: Luning Fang
  % =============================================================================

clc
clear all
close all
addpath('/Users/lulu/Documents/Research/code/friction3DSimEngine/core');
addpath('/Users/lulu/Documents/Research/code/friction3DSimEngine/helper');
addpath('/Users/lulu/Documents/Research/code/friction3DSimEngine/post_processing');


%%%%% 10^7 for k in normal force  %%%%

% bowling ball parameters

PI = 3.1415926;
mass = 5;

% ellipsoid
% radius_a = 0.2; radius_b = 0.18; radius_c = 0.15;
% c >> a = b
%radius_a = 0.5; radius_b = 0.2; radius_c = 0.2;
radius_a = 0.2; radius_b = 0.2; radius_c = 0.5;


% look up bowling isle statistics, a lot smaller friction coefficient
gravity = 9.8;
mu_s = 0.25;
mu_k = 0.2;

% use eta here for the energy tie between rolling and sliding
eta = 0.0001;  % choose eta to be about 1


scenario = sprintf('ellipsoid_easyRolling_eta_%dE-4_v_1_moredamping', eta*10^4);
Tend = 8; dt = 1e-4;
mySimulation = simulationProcess(Tend, dt, scenario);
t = 0:mySimulation.dt:mySimulation.endTime;

etaSpin = 0.05;

% tech_report = false;
% tech_report_dir = '/Users/lulu/Documents/TechReports/Friction3D/Images/';

% initialize kinematics array
pos = zeros(length(t),3); velo = zeros(length(t),3); acc = zeros(length(t),3);
eulerPar = zeros(length(t),4); omic = zeros(length(t),3); omic_dot = zeros(length(t),3);

% sliding friction parameter
Ke = 5e4;

normalForceStiffness = 1e7;



M_spin = zeros(length(t),1);
F_slide = zeros(length(t),1);
M_roll = zeros(length(t),1);


% create an ellipsoid with initial condition
myEllipsoid = ellipsoidClass(radius_a, radius_b, radius_c, mass);

% initial condition
initialVelocity = [0; 1; 0];
initialPosition = [0; 0; radius_a - myEllipsoid.mass*gravity/normalForceStiffness];
%initialOmic = [2; 1; 3];
initialOmic = [0;0;0];
initialOrientation = [0 0 1; -1 0 0; 0 -1 0];
initialEulerParameter = getPfromA(initialOrientation);


myEllipsoid.position = initialPosition;
myEllipsoid.velo = initialVelocity;
myEllipsoid.omic = initialOmic;
myEllipsoid.orientation = initialOrientation;
myEllipsoid.eulerParameter = initialEulerParameter;

% create a plane using normal direction and offset
groundNormal = [0;0;1];
groundOrigin = [0;0;0];
myPlane = planeClass(groundNormal, groundOrigin);

% get contact point, project onto the plane
contactPoint_prev = myEllipsoid.findContactPointWithPlane(myPlane);

initiationOfContact = true;
isInContact = false;

forceGravity = myEllipsoid.mass * [0; 0; -gravity];


slidingFr_holder = zeros(length(t),1);
rollingTr_holder = zeros(length(t),1);
contactPoint_holder = zeros(length(t), 3);
kineticEnergy_holder = zeros(length(t),1);
pos_holder = zeros(length(t), 3);
kineticEnergy_holder(1) = myEllipsoid.getKineticEnergy;

% holder for analysis of damping component of rolling resistence
curv_holder = zeros(length(t),1);
staticSlack_holder = zeros(length(t),1);
dampingCr_holder = zeros(length(t),1);
mode_holder = zeros(length(t),1);
normalForce_holder = zeros(length(t),1);
penetrationDepth_holder = zeros(length(t),1);
rollinghistory_holder = zeros(length(t), 1);


figHdl = figure;
figHdl.Units = 'normalized';
figHdl.Position = [0 0.4 0.84 0.5];
mySimulation.generateFrameStruct(150);
mySimulation.generateMovie = true;

for i = 1:length(t)-1
    
    % in contact, calculate and sum all the forces
    if myEllipsoid.isInContactWithPlane(myPlane) == true
        % in contact
        isInContact = true;
        % get penetration depth
        penetrationDepth = myEllipsoid.getPenetrationDepth(myPlane);
        % get normal force
        forceNormal = penetrationDepth * normalForceStiffness * groundNormal;
        
        %
        normalForce_holder(i+1) = norm(forceNormal);
        penetrationDepth_holder(i+1) = norm(penetrationDepth);
        
        % initiation of the contact, create contact object
        if initiationOfContact == true
            initiationOfContact = false;
            myContact = ellipsoidPlaneContactModel(myEllipsoid, myPlane);
            curv = myEllipsoid.getCurvatureAtLocalPt(myContact.CP_curr_local);
            myFrictionModel = frictionModel(mu_s, mu_k, Ke, eta, forceNormal, myEllipsoid, mySimulation.dt, curv);
            myFrictionModel.etaSpin = etaSpin;
            myFrictionModel.updateFrictionStiffnessAndSlack(curv, myEllipsoid, forceNormal);
            
        else
            % contact continue, update contact object
            myContact.updateContactAtNextTimeStep(myEllipsoid, myPlane);
            curv = myEllipsoid.getCurvatureAtLocalPt(myContact.CP_curr_local);
            
            % update slack and damping as well for ellipsoid
            myFrictionModel.updateFrictionStiffnessAndSlack(curv, myEllipsoid, forceNormal);
            
        end
        
        pi = geodesic(myContact.CP_prev_global_curr, myContact.CP_curr_global, ...
            myContact.CF_curr_global.n, myEllipsoid.position, false);  % body i for sphere
        pj_bar = myContact.CP_curr_global - myContact.CP_prev_global; % body j for the ground
        
        % frame for the ground
        CF_ground_u1bar = myContact.CF_prev_global.u;
        CF_global_u1    = myContact.CF_curr_global.u;
        CF_global_n1    = myContact.CF_curr_global.n;
        
        % calculate cos(psi) value
        % NOTE: small angle, cos(psi) close to 1
        psi_cos = min(1, CF_ground_u1bar'*CF_global_u1/sqrt(sum(CF_ground_u1bar.^2) * sum(CF_global_u1.^2)));
        
        % determine spin angle direction
        if dot(cross(CF_ground_u1bar, CF_global_u1), CF_global_n1) > 0
            psi = acos(psi_cos);
        else
            psi = -acos(psi_cos);
        end
        
        % rotate pj_bar back by psi
        pj = rotationAboutAxis(pj_bar, groundNormal, -psi);
        
        % find relative slide and roll
        delta = pj - pi;
        excursion = pi * myEllipsoid.getCurvatureAtLocalPt(myContact.CP_curr_local);
        
        myFrictionModel.updateFrictionParameters(delta, excursion, psi);
        myFrictionModel.evaluateForces;
        % do this last after evaluating of psi and delta Sij etc
        % replace previous contact frame and contact point
        myContact.replacePreviousContactFrame;
        myContact.replacePreviousContactPoint;
        
        % get all the forces and moments from contact model
        
        % sliding friction
        Fr_sliding = - myFrictionModel.slidingFr.totalFriction;
        % sliding friction torque wrt center of mass
        M_slidingFr   = cross(myContact.CP_curr_global - myEllipsoid.position, Fr_sliding);
        % normal force torque wrt center of mass
        M_normalForce = cross(myContact.CP_curr_global - myEllipsoid.position, forceNormal);
        
        % normalized radius
        r_norm = (myContact.CP_curr_global - myEllipsoid.position)/norm(myContact.CP_curr_global - myEllipsoid.position);
        % rolling torque
        M_rolling = cross(r_norm, myFrictionModel.rollingTr.totalFriction);
        % spinning torque
        M_spinning = -myFrictionModel.spinningTr.totalFriction * myContact.CF_curr_global.n;
        
        % sum all the forces and moments
        F_total = forceGravity + forceNormal + Fr_sliding;
        
        % sum all the moments
        M_total = M_slidingFr + M_normalForce + M_spinning + M_rolling...
            - tensor(myEllipsoid.omic') * myEllipsoid.inertiaMatrix * myEllipsoid.omic;
        
        
    end
    
    
    
    % not in contact
    if myEllipsoid.isInContactWithPlane(myPlane) == false
        
        isInContact = false;
        initiationOfContact = true;
        F_total = forceGravity;
        M_total = - tensor(myEllipsoid.omic') * myEllipsoid.inertiaMatrix * myEllipsoid.omic;
        
        
        
    end
    
    
    % update acceleration at new timestep
    myEllipsoid.acc = myEllipsoid.massMatrix\F_total;
    myEllipsoid.omic_dot = myEllipsoid.inertiaMatrix\M_total;
    myEllipsoid.updateKinematics(myEllipsoid.acc, myEllipsoid.omic_dot, mySimulation.dt);
    
    if isInContact == true
        % print out data
        sliding_Fr = myFrictionModel.slidingFr;
        rolling_Tr = myFrictionModel.rollingTr;
        spinning_Tr = myFrictionModel.spinningTr;
        %     fprintf('t=%.4f, KE = %g, rollingFrictionMode = %s\n', ...
        %         t(i), myEllipsoid.getKineticEnergy, myFrictionModel.rollingTr.mode);
        if mod(i, 1000) == 0
            fprintf('t=%.4f, Kr=%g, Dr=%g\n', t(i), myFrictionModel.rollingTr.stiffness, myFrictionModel.rollingTr.dampingCr);
        end
        %     fprintf('t=%.4f, Sij=%g, d_Sij=%g, Fr(%s):%g=%g+%g, Tr(%s):%g=%g+%g\n', ...
        %         t(i), norm(sliding_Fr.history), norm(sliding_Fr.increment), ...
        %         sliding_Fr.mode, norm(sliding_Fr.totalFriction), norm(sliding_Fr.elasticComponent), norm(sliding_Fr.plasticComponent), ...
        %         rolling_Tr.mode, norm(rolling_Tr.totalFriction), norm(rolling_Tr.elasticComponent), norm(rolling_Tr.plasticComponent));
        %     fprintf('t=%.4f\n', t(i));
        %     myFrictionModel.printOutInfo;
        %     fprintf('-------------\n')
        %     fprintf('F_total = [%g, %g, %g]\n', F_total(1), F_total(2), F_total(3));
        %     fprintf('M_total = [%g, %g, %g]\n', M_total(1), M_total(2), M_total(3));
        
        slidingFr_holder(i+1) = sliding_Fr.totalFriction(2);
        rollingTr_holder(i+1) = rolling_Tr.totalFriction(2);
        contactPoint_holder(i+1,:) = myContact.CP_curr_global';
        
        curv_holder(i+1) = curv;
        staticSlack_holder(i+1) = rolling_Tr.slackStatic;
        dampingCr_holder(i+1) = rolling_Tr.dampingCr;
        rollinghistory_holder(i+1) = norm(rolling_Tr.history);
        
        if strcmp(rolling_Tr.mode, 's')
            mode_holder(i+1) = 1;
        else
            mode_holder(i+1) = 0;
        end
        
        
    end
    kineticEnergy_holder(i+1) = myEllipsoid.getKineticEnergy;
    pos_holder(i+1,:) = myEllipsoid.position';
    
    
    %     viewIndexX = [18, 0,  0];  % side view, top view, front view
    %     viewIndexY = [10, 90, 0];
    FS = 25;
    LW = 2;
    
    if mySimulation.generateMovie == true &&  mod(i, floor(length(t)/mySimulation.movieLoops)) == 0
%    if mySimulation.generateMovie == true

        %            subplot(2,2,ii)
            myEllipsoid.drawReferenceFrame('r');
            hold on
            myPlane.drawPlane(-2.5,2.5);
                        grid off

            myEllipsoid.drawEllipsoid;
                        grid off

            %        myPlane.drawPlane(-0.5, 0.5);
            xlabel('x', 'FontSize', FS);
            ylabel('y', 'FontSize', FS);
            zlabel('z', 'FontSize', FS);

            view(74, 14) % front view
            axis equal
            xlim([-0.5, 0.5]);
            ylim([-0.5, 2.5]);  %
            zlim([0, 0.4]);
            textHdl = text(min(xlim), min(ylim), max(zlim)*1.2, ...
                sprintf('time = %.4gsec, KE=%g \n sliding mode:%s, Fr=%.2gN \n rolling mode:%s, Tr=%.2gNm', ...
                t(i), myEllipsoid.getKineticEnergy, ...
                sliding_Fr.mode, sliding_Fr.totalFriction(2),...
                rolling_Tr.mode, rolling_Tr.totalFriction(1)));
            textHdl.FontSize = FS+5;
            set(gca, 'linewidth', LW);
            set(gca, 'FontSize', FS-3);
            myContact.CF_curr_global.drawContactFrame(myContact.CP_curr_global, 'g', myEllipsoid.c*0.8);
                        grid off

            mySimulation.writeCurrentFrame;
            
            
            hold off
    end
    
end

%%
if mySimulation.generateMovie == true
    mySimulation.writeMovies(mySimulation.name);
end

%%
figure;
LW = 1;  % line width
FS = 20; % font size
MS = 8; % marker size
Tstart = 0;
Tend = Tend;

subplot(2,4,1);
makePlot(t, kineticEnergy_holder, '', 'Kinetic Energy(kgm^2/s^2)', '$$Dr = 2\sqrt{I Kr}$$', LW, FS);
xlim([Tstart,Tend]);


subplot(2,4,2);
makePlot(t, rollingTr_holder, '', 'total rolling torque(Nm)', '', LW, FS);
xlim([Tstart,Tend]);

subplot(2,4,3);
makePlot(t, slidingFr_holder, '', 'sliding friction(N)', '', LW, FS);
xlim([Tstart,Tend]);

subplot(2,4,4);
makePlot(t, dampingCr_holder, '', 'damping coefficient(Nms/rad)', '', LW, FS);
xlim([Tstart,Tend]);

subplot(2,4,5);
makePlotYY(t, staticSlack_holder, t, rollinghistory_holder, '', 'static slack (rad)', 'rolling history','', LW, FS);
xlim([Tstart,Tend]);

subplot(2,4,6);
myPlot = makePlot(t, mode_holder, '', 'rolling mode', 'static mode == 1', LW, FS);
myPlot.Marker = 'o'; myPlot.LineStyle = 'none'; myPlot.MarkerSize = MS;
xlim([Tstart,Tend]);

subplot(2,4,7);
makePlotYY(t, normalForce_holder, t, penetrationDepth_holder, '', 'normal force(N)', 'penetration(m)', '', LW, FS);
xlim([Tstart,Tend]);