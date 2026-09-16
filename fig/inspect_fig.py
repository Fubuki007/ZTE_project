# -*- coding: utf-8 -*-
import os, sys

p = r'D:\AA 学习项目\AAA 智能反射面辅助通信感知\AAA ZTE_project\fig\fig_velocity_rmse_vs_snr_4methods_beta100_server_edited.fig'
data = open(p, 'rb').read()
print('size =', len(data))
print('head116 =', data[:116])
print('head116 ascii:')
print(data[:116].decode('ascii', errors='replace'))
print('bytes 116:128 =', data[116:128])
print('tail80 =', data[-80:])
