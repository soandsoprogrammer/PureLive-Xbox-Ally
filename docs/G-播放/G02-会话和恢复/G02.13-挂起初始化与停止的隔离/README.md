# G02.13 挂起初始化与停止的隔离

初始化超时后隔离旧创建，允许有上限的替换；停止中的内核不被新房间复用，释放不无限等；增加有限脱敏原生阶段诊断。

来源：https://github.com/wzgrx/PureLive/issues/33；https://github.com/wzgrx/PureLive/issues/49。调研见本地purelive-root-causes-20261031。原设备尚无5.4.24同序列复验，不能把受控故障注入或AVD成功当作原机根因已闭环。
