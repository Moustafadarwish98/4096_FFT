clc;
clear;
close all;

% ============================================================
% PARAMETERS (MUST MATCH HDL TESTBENCH)
% ============================================================
N = 4096;              % FFT size
TONE_BIN = 2000;       % Same bin used in HDL stimulus
NUM_PEAKS = 5;         % Number of peaks to report

% ============================================================
% READ HDL FFT OUTPUT FILE
% ============================================================
data = readmatrix('fft_output.txt');

bin        = data(:,1);
real_part  = data(:,2);
imag_part  = data(:,3);

% Reconstruct complex FFT output
X_hdl = real_part + 1j * imag_part;

% Magnitude
mag_hdl = abs(X_hdl);
% ============================================================
% FIND HDL PEAKS
% ============================================================
[pk_vals_hdl, pk_idx_hdl] = maxk(mag_hdl, NUM_PEAKS);

fprintf('\n===============================\n');
fprintf('Before normalization Top %d Peaks (MATLAB FFT)\n', NUM_PEAKS);
fprintf('===============================\n');

for k = 1:NUM_PEAKS
    fprintf('Peak %d → Bin %d | Magnitude = %.2f\n', ...
        k, pk_idx_hdl(k)-1, pk_vals_hdl(k));
end

% Normalize HDL magnitude
mag_hdl = mag_hdl / max(mag_hdl);

% ============================================================
% GENERATE MATCHING MATLAB SIGNAL
% ============================================================
n = 0:N-1;

x = cos(2*pi*TONE_BIN*n/N);

% MATLAB FFT
X_mat = fft(x, N);
mag_mat = abs(X_mat);
% ============================================================
% FIND MATLAB PEAKS
% ============================================================
[pk_vals_mat, pk_idx_mat] = maxk(mag_mat, NUM_PEAKS);

fprintf('\n===============================\n');
fprintf('Before normalization Top %d Peaks (MATLAB FFT)\n', NUM_PEAKS);
fprintf('===============================\n');

for k = 1:NUM_PEAKS
    fprintf('Peak %d → Bin %d | Magnitude = %.2f\n', ...
        k, pk_idx_mat(k)-1, pk_vals_mat(k));
end

% Normalize MATLAB magnitude
mag_mat = mag_mat / max(mag_mat);

% ============================================================
% UN-SHIFTED COMPARISON
% ============================================================
figure;
plot(bin, mag_hdl, 'LineWidth', 1.2);
hold on;
plot(0:N-1, mag_mat, '--', 'LineWidth', 1.2);

legend('HDL','MATLAB');
grid on;

xlabel('FFT Bin');
ylabel('Normalized Magnitude');
title('Normalized MATLAB vs HDL FFT');

% ============================================================
% APPLY FFTSHIFT (CENTERED SPECTRUM)
% ============================================================
mag_hdl_shift = fftshift(mag_hdl);
mag_mat_shift = fftshift(mag_mat);

freq = -N/2 : N/2-1;

figure;
plot(freq, mag_hdl_shift, 'LineWidth', 1.2);
hold on;
plot(freq, mag_mat_shift, '--', 'LineWidth', 1.2);

legend('HDL','MATLAB');
grid on;

xlabel('Shifted Frequency Bin');
ylabel('Normalized Magnitude');
title('Centered MATLAB vs HDL FFT');

% ============================================================
% dB SCALE PLOT
% ============================================================
figure;
plot(freq, 20*log10(mag_hdl_shift + eps), 'LineWidth', 1.2);
hold on;
plot(freq, 20*log10(mag_mat_shift + eps), '--', 'LineWidth', 1.2);

legend('HDL','MATLAB');
grid on;

xlabel('Shifted Frequency Bin');
ylabel('Magnitude (dB)');
title('Centered MATLAB vs HDL FFT (dB)');

% ============================================================
% FIND PEAKS (HDL)
% ============================================================
[pk_hdl, idx_hdl] = maxk(mag_hdl, NUM_PEAKS);

fprintf('\n===============================\n');
fprintf('After Normalization Top %d Peaks (HDL FFT)\n', NUM_PEAKS);
fprintf('===============================\n');

for k = 1:NUM_PEAKS
    fprintf('Peak %d → Bin %d | Magnitude = %.4f\n', ...
        k, bin(idx_hdl(k)), pk_hdl(k));
end

% ============================================================
% FIND PEAKS (MATLAB)
% ============================================================
[pk_mat, idx_mat] = maxk(mag_mat, NUM_PEAKS);

fprintf('\n===============================\n');
fprintf('After Normalization Top %d Peaks (MATLAB FFT)\n', NUM_PEAKS);
fprintf('===============================\n');

for k = 1:NUM_PEAKS
    fprintf('Peak %d → Bin %d | Magnitude = %.4f\n', ...
        k, idx_mat(k)-1, pk_mat(k));
end

% ============================================================
% DOMINANT BIN CHECK
% ============================================================
[~, strongest] = max(mag_hdl);
dominant_bin = bin(strongest);

fprintf('\n===============================\n');
fprintf('Dominant HDL Bin = %d\n', dominant_bin);
fprintf('Mirror Bin       = %d\n', mod(N-dominant_bin, N));
fprintf('===============================\n');

% ============================================================
% FFTSHIFT VIEW (Centered Spectrum)
% ============================================================
figure;
plot(-N/2:N/2-1, fftshift(mag_hdl), 'LineWidth', 1.2);
grid on;

xlabel('Shifted Frequency Bin');
ylabel('Magnitude');
title('HDL FFT (Centered using fftshift)');

% ============================================================
% FFTSHIFT VIEW (Centered Spectrum)
% ============================================================
mag_hdl = abs(real_part + 1j*imag_part);
mag_hdl = mag_hdl / max(mag_hdl);

mag_mat = abs(fft(x));
mag_mat = mag_mat / max(mag_mat);

figure;
plot(bin, mag_hdl, 'LineWidth', 1.2);
hold on;
plot(0:N-1, mag_mat, '--', 'LineWidth', 1.2);
legend('HDL','MATLAB');
grid on;
xlabel('FFT Bin');
ylabel('Normalized Magnitude');
title('Normalized MATLAB vs HDL FFT');
% ============================================================
% OPTIONAL: DISPLAY DOMINANT BIN PAIR
% ============================================================
[~, strongest] = max(mag_hdl);
dominant_bin = bin(strongest);

fprintf('\n===============================\n');
fprintf('Dominant HDL Bin = %d\n', dominant_bin);
fprintf('Mirror Bin       = %d\n', mod(N-dominant_bin, N));
fprintf('===============================\n');
% ============================================================
% FIND MATLAB PEAKS
% ============================================================
[pk_vals_mat, pk_idx_mat] = maxk(mag_mat, NUM_PEAKS);

fprintf('\n===============================\n');
fprintf('Top %d Peaks (MATLAB FFT)\n', NUM_PEAKS);
fprintf('===============================\n');

for k = 1:NUM_PEAKS
    fprintf('Peak %d → Bin %d | Magnitude = %.2f\n', ...
        k, pk_idx_mat(k)-1, pk_vals_mat(k));
end
