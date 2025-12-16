%% Section 1
% Create a time vector (3 days, 1-minute steps)
time_sim = (0:60:30*24*3600)'; 
% Create a temperature curve (283.15 K base for 10C, 5 K swing)
T_ambient_K = 283.15 + 5 * sin((2*pi*time_sim)/(24*3600)); 
% Combine into a Simulink data structure: [Time, Data]
weather_data = [time_sim, T_ambient_K];


%% section 2
% --- SAFETY CHECK: Find the logsout variable ---
if exist('out', 'var')
    % If MATLAB saved the result as 'out', extract logsout from it
    logsout = out.logsout;
elseif ~exist('logsout', 'var')
    % If neither exists, stop and warn the user
    error('Error: Simulation data not found! Please RUN the Simulink model first.');
end

% 1. Extract the primary Time and Data vectors (Assuming Ti is the first element)
Ti_log_element = logsout.getElement('ti'); % Get the Simulink.SimulationData.Signal object
Time_data_raw = Ti_log_element.Values.Time; % Extract the raw time vector (double)
Ti_data_raw = Ti_log_element.Values.Data;   % Extract the raw data vector (double)

% 2. Define a uniform time vector (every 60 seconds) for interpolation
t_start = Time_data_raw(1);
t_end = Time_data_raw(end);
uniform_time = (t_start:60:t_end)'; % Forced 60-second intervals

% 3. Extract and Resample all signals using linear interpolation (interp1)

% Extract data for Ti, Qheater, Tamb, Qinternal (Adjust names if needed)
Qheater_data_raw = logsout.getElement('Q_heater').Values.Data;
Tamb_data_raw = logsout.getElement('t_amb').Values.Data;
Qinternal_data_raw = logsout.getElement('q_internal').Values.Data;

% Perform resampling using linear interpolation (interp1)
Ti_data = interp1(Time_data_raw, Ti_data_raw, uniform_time, 'linear');
Qheater_data = interp1(Time_data_raw, Qheater_data_raw, uniform_time, 'linear');
Tamb_data = interp1(Time_data_raw, Tamb_data_raw, uniform_time, 'linear');
Qinternal_data = interp1(Time_data_raw, Qinternal_data_raw, uniform_time, 'linear');

% --- CORRELATION CHECK (for verification) ---
% Remove the last time step for current state/action vectors
Ti_current = Ti_data(1:end-1);
Ti_next = Ti_data(2:end);
Qheater_prev = Qheater_data(1:end-1); 

% Calculate the crucial correlations
corr_Ti = corr(Ti_current, Ti_next, 'rows','complete'); % Ignore NaNs
corr_Qheater_Ti = corr(Qheater_prev, Ti_next, 'rows','complete');

disp(['Correlation (Ti_current, Ti_next) AFTER INTERP: ', num2str(corr_Ti)]);
disp(['Correlation (Q_heater_prev, Ti_next) AFTER INTERP: ', num2str(corr_Qheater_Ti)]);

% --- EXPORT TO CSV (Full Script) ---
disp('Exporting clean CSV...');

% Calculate Time-of-Day feature (using the new uniform time vector)
Hour_of_Day = mod(uniform_time / 3600, 24); 

% Combine into a table
DataT = table(uniform_time, Hour_of_Day, Ti_data, Qheater_data, Tamb_data, Qinternal_data, ...
    'VariableNames', {'Time', 'Hour_of_Day', 'Ti_current', 'Q_heater_prev', 'T_ambient', 'Q_internal'});

% Create the Target Column (Ti at next step: T_i, t+1)
DataT.Ti_next = [DataT.Ti_current(2:end); NaN];

% Remove the last row (since its Ti_next is NaN)
DataT(end, :) = [];

% Export the final table to a CSV file
writetable(DataT, 'thermal_training_data.csv');
disp('Data export complete. thermal_training_data.csv is ready.');

%% section 3
% Import the ONNX file into a MATLAB object
net = importONNXNetwork('rf_thermal_predictor_optimal.onnx', ...
    'InputDataFormats','BC', ...
    'OutputDataFormats','BC');

disp('ONNX model imported successfully into MATLAB variable "net".');