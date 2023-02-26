# 浙江大学23年春夏学期系统贯通三实验

本[仓库](http://git.zju.edu.cn/zju-sys/sys2-fa22/)是浙江大学23年春夏**系统贯通三**课程的教学仓库，包含所有实验文档和公开代码。仓库目录结构：

```
├── README.md 
├── docs/       # 实验文档    
├── mkdocs.yml 
└── src/        # 公开代码
```



## 本地渲染文档

文档采用了 [mkdocs-material](https://squidfunk.github.io/mkdocs-material/) 工具构建和部署。如果想在本地渲染：

```
$ pip3 install mkdocs-material                      # 安装 mkdocs-material 
$ git clone https://gitee.com/Parfaity/sys3lab-2023-stu.git # clone 本 repo 
$ mkdocs serve                                      # 本地渲染 INFO     -  Building documentation... INFO     -  Cleaning site directory ... INFO     -  [11:00:57] Serving on http://127.0.0.1:8000/sys2-fa22/
```



## 致谢

感谢以下各位助教对本套课程实验的辛勤付出：

- Fa23：徐金焱、叶泽凯、赵小迪
- Fa22：潘子曰、朱若凡、季高强、郭若容、杜云潇
- Fa21：周侠、徐金焱、管章辉、张文龙、庄阿得、王琨、沈韬立、王星宇、朱璟森
- Fa20：刘强、孙家栋、徐金焱、谢洵、马麟
