## 变更摘要

## 关联需求 ID / 错误码

## 影响范围
- [ ] 导航 / 手势
- [ ] 手绘 / Mask
- [ ] 检测
- [ ] 图片修复
- [ ] 视频管线
- [ ] 导出 / 权限
- [ ] 调试面板
- [ ] UI / 可访问性
- [ ] 流水线 / 脚本

## 自测清单
- [ ] 本地 Debug + Release 构建通过（CODE_SIGNING_ALLOWED=NO）
- [ ] 单元测试通过
- [ ] 涉及视频/图片的在真机走查
- [ ] 处理中返回二次确认、取消 5s 内清理
- [ ] 未新增 print/NSLog
- [ ] Debug 相关代码在 #if DEBUG 内
- [ ] 新增/修改 UI 有暗色与横屏截图

## 截图 / 录屏

## 风险与回滚

## OpenCV bridge safety (修改 OpenCVBridge.mm 时必填)
- [ ] 已同步更新 `docs/OPENCV_BRIDGE_CONTRACT.md` 的契约表。
- [ ] 尺寸、16 MP、radius、buffer 长度校验均先于 cv::Mat 构造和 OpenCV 调用。
- [ ] 全零 mask 在桥接层直接返回原图，未进入 OpenCV。
- [ ] 高覆盖率且触边的 mask、边界参考像素不足的 mask 均会被拒绝。
- [ ] 已新增/更新合成 BGRA 回归测试。
- [ ] 未引入 C++ 异常/RTTI catch 逻辑。
- [ ] CI 无 abort 类崩溃。
