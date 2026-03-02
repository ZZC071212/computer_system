# 浙江大学26年春夏学期系统贯通三实验

本仓库是浙江大学26年春夏**系统贯通三**课程的教学仓库，包含所有实验文档和公开代码。仓库目录结构：

```
├── README.md
├── docs/       # 实验文档
├── repo/       # 工具链目录
├── mkdocs.yml
└── src/        # 实验代码
```
实验文档已经部署在了[ZJU Git pages](http://zju-sys.pages.zjusct.io/sys3/sys3-sp26)上，方便大家阅读。

## 实验安排

下图仅供参考，具体时间安排请大家注意实验课和钉钉通知。

::gantt::

- title: 26春夏系统III实验安排
  activities:
  - title: Lab1
    start: 2026-03-11
    lasts: 3 weeks
  - title: Lab2
    start: 2026-04-01
    lasts: 3 weeks
  - title: Lab3
    start: 2026-04-22
    lasts: 2 weeks
  - title: Lab4
    start: 2026-04-29
    lasts: 2 weeks
  - title: Lab5
    start: 2026-05-06
    lasts: 3 weeks
  - title: Project
    start: 2026-05-20
    lasts: 5 weeks

::/gantt::

### 诚信政策

!!! Danger
    详见[注意事项](https://zju-sys.pages.zjusct.io/sys3/sys3-sp26/notes/)，所有不遵守诚信要求的提交将会面临严肃惩罚。

### 迟交惩罚

!!! Warning
    所有迟交的实验将按照超过截止日期 10%/天 的标准扣除相应分数。

## 本地渲染文档

文档采用了 [mkdocs-material](https://squidfunk.github.io/mkdocs-material/) 工具构建和部署。如果想在本地渲染：

```
$ pip install mkdocs-material mkdocs-heti-plugin   # 安装依赖
$ git clone https://git.zju.edu.cn/zju-sys/sys3/sys3-sp26 # clone 本 repo
$ mkdocs serve                                     # 本地渲染
INFO     -  Building documentation...
...
INFO     -  [...] Serving on http://127.0.0.1:8000/sys3/sys3-sp26/
```

## 致谢

感谢以下各位助教对本套课程实验的辛勤付出：

- Sp26：张书怀、王鹤翔、曹语、蒋城昊、娄思妤、王文烁
- Sp25：张幸智、朱宝林、林轩永、叶泽凯、李英琦
- Sp24：王鹤翔、耿华、周杨叶
- Sp23：郑小叶、陈佳彤、汤尧、徐金焱
- Sp22：苑子琦、张行健、潘子曰、朱若凡、季高强、郭若容、杜云潇
- Fa21：周侠、徐金焱、管章辉、张文龙、庄阿得、王琨、沈韬立、王星宇、朱璟森
- Fa20：刘强、孙家栋、徐金焱、谢洵、马麟
