# X01.5 Windows启动布局与首帧恢复

统一启动显示控制；最终布局与首帧之间补有界子窗口同步，保留DPI、最大化、全屏、隐藏和焦点，不周期改变顶层窗口。

来源：https://github.com/wzgrx/PureLive/issues/47。调研见本地purelive-root-causes-20261031。原设备尚无5.4.24同序列复验，不能把受控故障注入或AVD成功当作原机根因已闭环。
