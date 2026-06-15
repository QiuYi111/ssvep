# 从 SSVEP 到场景化注意力训练：我们为什么这样设计本系统

过去这些年，注意力训练设备并不少见。很多系统会把前额叶的 beta 功率，或者 theta/beta 比值，当作“专注度”的替代指标。这样的路线并不是没有依据，它确实建立在一批神经反馈研究之上，也在 ADHD 等领域形成过相当长时间的应用传统。但问题在于，这类指标常常更像是在测一个人“整体上是不是比较清醒、紧张、投入”，却不太擅长回答另一个更关键的问题：这个人的注意力，此刻到底落在了哪里。对于真正想训练空间选择性注意、抗干扰能力和目标保持能力的系统来说，这个缺口其实很致命。([PNAS](https://www.pnas.org/doi/10.1073/pnas.93.10.4770?utm_source=chatgpt.com "Selective attention to stimulus location modulates the ..."))

也正因为如此，我们越来越觉得，注意力训练如果还停留在“让一根能量条升起来”的层面，其实是有些浪费神经科学已经给出的机会的。稳态视觉诱发电位，也就是 SSVEP，提供的是另一条路线。它的优势并不神秘：当不同空间位置的目标以不同频率闪烁时，视觉皮层会在对应频率上产生稳定响应；而当注意力真正聚焦到某一个目标时，这个目标对应的 SSVEP 幅值会增强。Morgan、Hansen 和 Hillyard 在 1996 年就已经证明，空间选择性注意会调制 SSVEP；随后 Kim 等人在 2007 年进一步指出，这种增强不是随便涨一点，而更像是一种与同步化有关的 response gain。换句话说，SSVEP 不只是告诉我们“大脑亮没亮”，它更接近于告诉我们“大脑把资源投给了谁”。([PNAS](https://www.pnas.org/doi/10.1073/pnas.93.10.4770?utm_source=chatgpt.com "Selective attention to stimulus location modulates the ..."))

更重要的是，这件事不是只能在教科书里成立。近年的实时追踪研究已经表明，SSVEP 功率的瞬时波动可以作为注意状态的可靠读出，而且可以进入闭环系统。Chinchani 等人在 2022 年的认知脑机接口研究里，直接用 SSVEP power dynamics 去追踪 momentary fluctuations in attention，并且发现这种状态读出与后续行为表现有明确关系。也就是说，SSVEP 不是一个“事后解释用”的指标，它可以被拿来做训练中的实时反馈。([PubMed](https://pubmed.ncbi.nlm.nih.gov/36481698/?utm_source=chatgpt.com "Tracking momentary fluctuations in human attention ... - PubMed"))

这正是本系统要解决的问题：我们并不满足于做一个“测专注”的工具，而是想做一个能够训练“把注意力稳定地投向正确目标，并在干扰中维持这种投向”的系统。这个目标听上去很朴素，但它其实更接近临床和真实生活里的困难本体。无论是 ADHD 儿童在教室里的走神，还是高压环境下的目标保持，真正困难的从来不是“我有没有努力”，而是“我的注意力是不是能在复杂世界里待在它该待的地方”。

---

## Insights

本系统的结构，并不是先有一个美术故事，再去给它找神经科学解释；更像是相反。我们先看证据，然后一点点意识到，一个合理的系统大概就应该这么长出来。

第一层证据来自 SSVEP 本身的性质。既然它擅长表征空间指向性的注意，那训练任务就不应该只是单调地盯住一个闪烁点，而应该从“维持一个目标”逐步过渡到“在多个目标中选对一个”“在目标移动时继续跟随它”“在强干扰下拒绝被带走”。换句话说，如果底层指标本来就是空间性的，那上层任务设计也应该诚实地利用这种空间性，而不是把它浪费在一个静态分数条上。Morgan 等人的工作是这条思路的起点，Kim 等人的 response gain 研究则让我们更有信心相信：当用户真正把注意力稳定地落在目标上时，系统看到的不是噪声里的偶然波动，而是一个具有机制基础的增益变化。([PNAS](https://www.pnas.org/doi/10.1073/pnas.93.10.4770?utm_source=chatgpt.com "Selective attention to stimulus location modulates the ..."))

第二层证据来自实时性。既然 SSVEP 可以进入闭环，那么反馈就不应该只是训练结束后的一张报告，而应该体现在训练过程中。可这里马上出现一个设计分岔：反馈到底该怎么呈现？最简单的做法当然是分数、阈值、进度条、成功率，但我们越看越觉得，这种做法在工程上虽方便，在认知上却很粗糙。因为用户最后学会的，很可能是对某个抽象 UI 的追逐，而不是对目标本身的自然维持。Chinchani 等人的工作让我们确认，实时状态本身是可以被可靠读取的；而 Huang 等人在 2022 年的 AR-EEG 研究又往前推了一步，他们把 SSVEP 神经反馈真正用在了 affect-biased attention 的训练协议里，证明这种实时反馈不仅能“测”，也能“练”。这给了我们一个很明确的提示：闭环反馈一定要有，但它不必非得长成医疗仪器的样子。([PubMed](https://pubmed.ncbi.nlm.nih.gov/36481698/?utm_source=chatgpt.com "Tracking momentary fluctuations in human attention ... - PubMed"))

第三层证据来自干预场景。注意力训练真正有价值的地方，通常都不发生在一个没有干扰的真空里。ADHD 之所以难，并不是因为孩子看不见目标，而是因为别的东西太容易把他拉走。情感偏向训练之所以重要，也不是因为人们不知道任务目标在哪，而是因为某些高显著性的刺激太容易劫持选择性注意。Huang 等人的增强现实方案，恰恰抓住了这种竞争结构：任务相关刺激和情绪干扰刺激同时存在，系统不再笼统地问“你有没有专注”，而是更尖锐地问“你把资源分给了谁”。这个问题一旦成立，本系统后续那些有目标、有干扰、有竞争、有切换的关卡结构，其实就顺理成章了。([PubMed](https://pubmed.ncbi.nlm.nih.gov/36085716/?utm_source=chatgpt.com "Using Neurofeedback from Steady-State Visual Evoked ..."))

还有一层经常被忽略，但对系统设计影响非常大的证据，是关于视觉舒适度和频率选择的。很多早期 SSVEP 方案喜欢用低频、强对比、显眼闪烁，因为信号大、好识别；但如果目标是长期训练而不是一次性实验，那么舒适度就变成了硬约束。相关综述和实验工作不断提醒我们：高频、低显著、局部化、语义自然化的刺激，更有可能兼顾检测与耐受。换句话说，本系统后来坚持把闪烁“藏进”星点、萤火、水面高光、云层边缘等自然元素里，不是为了包装，而是因为它确实更接近一个可长期使用系统该有的刺激哲学。([MDPI](https://www.mdpi.com/2076-3417/14/21/9855?utm_source=chatgpt.com "A Systematic Review of BCI-AR Systems"))

---

## 介绍

于是系统最后变成了现在这个样子：前面有一个标定系统，后面接六个训练关卡。这个结构表面上很像内容编排，实际上更像把神经工程流程重新翻译成用户能接受的体验顺序。

标定系统之所以放在最前面，不只是因为任何脑机接口都需要校准，更因为 SSVEP 训练如果不做个体化，后面的所有优雅都容易变成表演。不同个体对不同频率的响应强度不同，同一个人不同天的状态也不同。标定系统做的其实是几件很朴素的事情：检查枕叶通道的信号质量，快速扫频，看今天哪个频率窗口的响应更稳定，顺便估计用户当日的可用信噪比。只是我们不想让这件事长得像“设备自检”，而希望它更像进入训练前的一次安静对时。它不是为了增加仪式感，而是为了把“生理接口对齐”这件必要但突兀的事情，放进一个更顺滑的入口里。临床上这一步越稳，后面的闭环才越不会失真。([PubMed](https://pubmed.ncbi.nlm.nih.gov/36481698/?utm_source=chatgpt.com "Tracking momentary fluctuations in human attention ... - PubMed"))

六个关卡的排序，则来自一个很朴素的判断：如果底层训练目标是注意力控制，那么它就不应该一上来就要求用户在复杂干扰中表现完美。它需要一个从“维持”到“选择”、从“切换”到“抵抗诱惑”的梯度。

第一关把难度压得很低。用户面对的是一个很稳定、很单纯的目标，任务只是把注意力安静地放上去，并持续一段时间。我们想训练的不是“会不会玩”，而是最基本的 sustained attention。这个阶段里，反馈也必须足够温和，因为系统和用户都在彼此熟悉：系统在读这个人的 SSVEP，用户也在逐渐形成一种经验——当我真的把注意放稳，世界会发生什么变化。

第二关开始把目标变得更微小、更环境化一些。这里的核心其实不是“更好看”，而是让持续性注意不再依赖一个特别明显的中心刺激，而变成对一簇局部光点的稳定跟随。我们关心的是视觉耐力，也关心疲劳阈值。一个系统如果只能在非常显眼的刺激上工作，那它的训练价值会很有限；能让人在更细小、更自然的目标上维持注意，才更接近未来可迁移的能力。

第三关把问题从“盯住一个东西”变成“按顺序找到下一个东西”。这时系统开始碰触转移性注意。我们不希望切换任务做得像点击 UI，而更像在空间里逐点连接线索。因为在很多真实场景中，注意力不是静止的，它得在几个候选点之间有序地流动，但又不能一下子散开。SSVEP 在这里的价值特别明显：它并不只是测单点强不强，而是能在多个频率标签之间看竞争关系。

第四关真正把选择性注意和抑制控制推到台前。目标和干扰并存，而且干扰不能设计得太笨。否则用户训练到的只会是“看到最亮的那个”，而不是“拒绝错误的那个”。这一关对我们很关键，因为它最直接对接临床上最关心的一个维度：在高显著刺激不断入侵时，个体是否还能够把资源留给正确目标。做这关的时候，我们不断提醒自己，训练的本质不是强化“看见”，而是强化“别被带走”。

第五关开始引入运动。目标不再静静待在原地，而是在空间中移动。只要目标一动，系统训练的内容就变了：这时候不仅是 selective attention，还开始涉及平滑追踪、动态更新和更快速的错误恢复。我们之所以把它设计成“追随某个引导物穿过干扰环境”，不是为了叙事上的戏剧性，而是因为动态场景会把很多实验室里看不见的脆弱性暴露出来。一个人在静止目标上表现不错，不代表他在运动目标和瞬态干扰里也能守住。

第六关则是整个系统最克制也最困难的一关。到这个阶段，我们反而把目标重新变得很简单：它几乎静止，真正难的是周围那些突然而诱人的东西。流星、飞掠物、闪变边缘，本质上都是为了测试一件事：当强显著事件闯入视野时，注意系统能不能不立刻跳过去。某种意义上，这一关练的不是“找到目标”，而是“允许别的事情发生，但我不被拖着走”。如果说前几关是在搭建注意的骨架，那么最后这关更像是在检验控制的筋膜有没有真正长出来。

---

## 美学

这件事可能最容易被误解。很多人一看到系统里有场景、有光影、有声音，就会条件反射地以为这部分属于“包装层”。可我们越往后做，越觉得它其实是方法学的一部分。

首先，注意力训练天然是一个高依从性要求的任务。它不会在三分钟内结束，也不会只做一次。任何需要重复进入、持续练习的系统，最后都会碰到一个非常现实的问题：用户愿不愿意回来。如果界面始终像一台体检仪器，那用户和系统之间建立的关系就会非常功利，甚至带点对抗意味。尤其是儿童、青少年或已经对“训练”二字有倦怠的人群，他们很容易在心理上把自己放到一个被测量、被纠正的位置。那种感觉未必有利于长期使用。

其次，更重要的一点是，SSVEP 的视觉刺激本身就需要被精细地安放。如果刺激裸露成闪烁块、频闪灯、对比条，它当然更容易被工程师调试，但这类刺激既容易疲劳，也容易让用户把训练经验和“忍受闪烁”绑定起来。我们坚持把这些刺激隐藏在自然视觉语义里，比如局部高光、微小发光体、水面反射、远处星点，不是为了“文艺化”，而是因为这种语义掩蔽更符合长期训练需要。它让系统的视觉语言看起来像一个完整世界，而不是一组被硬插进去的实验变量。某种意义上，这反而让科学性更完整：因为它迫使我们认真处理刺激面积、局部亮度、波形、色彩分层与视觉舒适度，而不是简单依赖“更亮、更闪、更好测”。([MDPI](https://www.mdpi.com/2076-3417/14/21/9855?utm_source=chatgpt.com "A Systematic Review of BCI-AR Systems"))

再者，美学并不只关乎视觉。闭环系统的反馈如果全都压在屏幕上，用户会很快疲倦。相反，当声音也被纳入反馈通道，训练状态就不再只是“看见一个结果”，而变成“处在一种被环境回应的状态里”。从工程角度看，这是多模态反馈；从使用者角度看，它更像一种更少对抗、更少评判的训练氛围。我们并不认为这种设计会自动带来疗效，但它确实更有希望带来稳定的使用关系。

所以，为什么我们坚持美学设计，而不是做成简单的医疗仪器风格？因为本系统的目标不是展示“我在测你”，而是尽可能减少系统本身对注意的额外打扰。一个好的训练界面，不应该一直提醒用户自己正在被训练。它应该尽量让目标、干扰和反馈都长在同一个世界里，让用户在那个世界里自然地把注意力放对地方。这件事表面上是审美，底层上其实是在减少无关认知负荷。

---

## 总结

写到这里，最需要说清楚的反而是边界。本系统现在更像一个有明确研究逻辑支撑的 demo，而不是一个已经完成严谨临床验证的标准治疗产品。SSVEP 作为空间注意力指标的科学基础是扎实的，实时追踪与闭环训练也已经有了相当关键的先行工作，但从“机制成立”到“临床有效、长期有效、可规模推广”之间，仍然隔着很多认真而缓慢的工作。比如，它是否真的优于传统前额叶 beta 神经反馈，是否能在 ADHD 人群中稳定迁移到课堂和生活，是否能在长期居家训练中维持效果，这些都不能靠系统设计本身来替代证据。([PubMed](https://pubmed.ncbi.nlm.nih.gov/36085716/?utm_source=chatgpt.com "Using Neurofeedback from Steady-State Visual Evoked ..."))

但即便如此，我们仍然觉得这个 demo 是有价值的。因为它试着回答了一个常被忽略的问题：如果我们真的把“空间化的注意力训练”当回事，那么系统应该长什么样？我们的回答是，它大概不该只是一个分数面板，也不该只是一个实验室范式的消费级移植。它需要一个认真做过个体化校准的入口，需要一条从持续性注意到高级抗干扰控制的渐进路径，需要把反馈真正嵌入任务本身，也需要承认审美和依从性不是附属变量，而是设计的一部分。

所以，与其说这是一篇宣布完成的文章，不如说它更像一份阶段性说明：我们依据已有证据，暂时把系统推到了这里。它还不够成熟，也远没有资格夸口改变临床实践，但至少它提供了一种我们认为值得继续验证的方向。注意力训练也许不必总是长成冷冰冰的仪器，它也可以更精确、更诚实，同时更愿意和人相处一点。

---

## 参考文献

Morgan ST, Hansen JC, Hillyard SA. Selective attention to stimulus location modulates the steady-state visual evoked potential.  *Proceedings of the National Academy of Sciences* . 1996;93(10):4770–4774. ([PNAS](https://www.pnas.org/doi/10.1073/pnas.93.10.4770?utm_source=chatgpt.com "Selective attention to stimulus location modulates the ..."))

Kim YJ, Grabowecky M, Paller KA, Muthu K, Suzuki S. Attention induces synchronization-based response gain in steady-state visual evoked potentials.  *Nature Neuroscience* . 2007;10:117–125. ([PubMed](https://pubmed.ncbi.nlm.nih.gov/17173045/?utm_source=chatgpt.com "Attention induces synchronization-based response gain in ..."))

Chinchani AM, et al. Tracking momentary fluctuations in human attention with a cognitive brain-machine interface.  *Communications Biology* . 2022. ([PubMed](https://pubmed.ncbi.nlm.nih.gov/36481698/?utm_source=chatgpt.com "Tracking momentary fluctuations in human attention ... - PubMed"))

Huang X, et al. Using neurofeedback from steady-state visual evoked potentials to target affect-biased attention in augmented reality.  *2022 IEEE EMBC* . ([PubMed](https://pubmed.ncbi.nlm.nih.gov/36085716/?utm_source=chatgpt.com "Using Neurofeedback from Steady-State Visual Evoked ..."))

Gall R, et al. AttentionCARE: replicability of a BCI for the clinical application of augmented reality-guided EEG-based attention modification for adolescents at high risk for depression.  *Frontiers in Human Neuroscience* . 2024. ([Frontiers](https://www.frontiersin.org/journals/human-neuroscience/articles/10.3389/fnhum.2024.1360218/full?utm_source=chatgpt.com "AttentionCARE: replicability of a BCI for the clinical ..."))
