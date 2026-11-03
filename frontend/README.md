# frontend — 管理后台

面向生产企业、物流企业、销售企业与监管部门的 Web 管理端。

## 技术栈

- Vue 3 + Vite
- Element Plus
- Pinia（状态管理）
- Vue Router
- ECharts（溯源统计可视化）
- Axios

## 规划页面

| 模块 | 页面 | 说明 |
| --- | --- | --- |
| 登录 | `/login` | 主体账号登录，区分角色 |
| 工作台 | `/dashboard` | 批次总览、环节分布、异常告警 |
| 批次管理 | `/batch` | 创建批次、查看批次列表 |
| 溯源录入 | `/batch/:id/trace` | 按角色录入本环节数据 |
| 溯源查询 | `/trace/:batchId` | 全链路时间轴展示 |
| 主体管理 | `/entity` | 监管方审核主体、分配角色 |
| 溯源码 | `/qrcode` | 批量生成与下载二维码 |
| 系统日志 | `/log` | 链上交易记录与操作审计 |

## 开发

```bash
npm install
npm run dev      # 开发模式，默认 5173
npm run build    # 生产构建
```

## 接口代理

`vite.config.js` 中配置 `/api` 代理到后端：

```js
server: {
  proxy: {
    '/api': {
      target: 'http://localhost:8080',
      changeOrigin: true
    }
  }
}
```

## 角色与菜单权限

菜单按登录主体角色动态渲染：生产主体（批次/种植/采收）、检测机构（质检提交）、物流企业（运输交接）、销售商（上架销售）仅可见本环节入口，监管方可见主体审核、全量审计与不合格处置。
