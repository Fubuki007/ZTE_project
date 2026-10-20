<!--
Source paper : RIS-Based Self-Interference Cancellation for Full-Duplex Broadband Transmission
Authors      : Jiayan Wu, Wenchi Cheng, Jianyu Wang, Jingqing Wang, Wei Zhang
arXiv        : arXiv:2407.12534v1 [eess.SP], 17 Jul 2024   DOI: 10.48550/arXiv.2407.12534
Extracted    : complete text, every equation (as LaTeX), all captions, both algorithms,
               and the full reference list -- nothing abridged.
Conventions  : * ``$$ ... \tag{n} $$``  display equations, numbered exactly as in the paper
               * inline maths kept as ``$...$`` (LaTeX), directly readable by an LLM
               * citation markers ``[n]`` follow the paper's own reference numbering
               * figures are marked ``> **Fig. N** - <caption>``; the graphics themselves
                 are images inside the PDF and are not reproduced here
-->

# RIS-Based Self-Interference Cancellation for Full-Duplex Broadband Transmission

**Authors:** Jiayan Wu, Student Member, IEEE, Wenchi Cheng, Senior Member, IEEE, Jianyu Wang, Student Member, IEEE, Jingqing Wang, Member, IEEE, and Wei Zhang, Fellow, IEEE

**Funding, affiliation and correspondence (first-page footnote):** This work was supported in part by National Key R&D Program of China under Grants 2021YFC3002102 and 2023YFC3011502, in part by the Key R&D Plan of Shaanxi Province under Grant 2022ZDLGY05-09, in part by the National Natural Science Foundation of China under Grant 62201427, and in part by Key Area Research and Development Program of Guangdong Province under Grant 2020B0101110003. (Corresponding author: Wenchi Cheng.) Jiayan Wu, Wenchi Cheng, Jianyu Wang, and Jingqing Wang are with the State Key Laboratory of Integrated Services Networks, Xidian University, Xi'an, 710071, China (e-mails: jiayanwu@stu.xidian.edu.cn, wccheng@xidian.edu.cn, jywang_0812@stu.xidian.edu.cn, wangjingqing00@g-mail.com). Wei Zhang is with the School of Electrical Engineering and Telecommunications, University of New South Wales, Sydney, NSW 2052, Australia (e-mail: w.zhang@unsw.edu.au).

## Abstract

Full-duplex (FD) is an attractive technology that can significantly boost the throughput of wireless communications. However, it is limited by the severe self-interference (SI) from the transmitter to the local receiver. In this paper, we propose a new SI cancellation (SIC) scheme based on reconfigurable intelligent surface (RIS), where small RISs are deployed inside FD devices to enhance SIC capability and system capacity under frequency-selective fading channels. The novel scheme can not only address the challenges associated with SIC but also improve the overall performance. We first analyze the near-field behavior of the RIS and then formulate an optimization problem to maximize the SIC capability by controlling the reflection coefficients (RCs) of the RIS and allocating the transmit power of the device. The problem is solved with alternate optimization (AO) algorithm in three cases: ideal case, where both the amplitude and phase of each RIS unit cell can be controlled independently and continuously, continuous phases, where the phase of each RIS unit cell can be controlled independently, while the amplitude is fixed to one, and discrete phases, where the RC of each RIS unit cell can only take discrete values and these discrete values are equally spaced on the unit circle. For the ideal case, the closed-form solution to RC is derived with Karush-Kuhn-Tucker (KKT) conditions. Based on Riemannian conjugate gradient (RCG) algorithm, we optimize the RC for the case of continuous phases and then extend the solution to the case of discrete phases by the nearest point projection (NPP) method. Simulation results are given to validate the performance of our proposed SIC scheme.

**Index Terms—** Reconfigurable intelligent surface (RIS), full-duplex (FD), self-interference cancellation (SIC), near-field, orthogonal frequency division multiplexing (OFDM).


## I. Introduction

Full-duplex (FD) has gained substantial attention in recent years and is widely considered as an effective technology to enhance the spectrum efficiency. Compared with traditional half-duplex (HD), FD can potentially double the spectrum efficiency, thus inherently increasing the capacity of wireless networks. However, FD faces the problem of how to deal with the self-interference (SI) [1], [2], [3].

Reconfigurable intelligent surface (RIS) is an emerging material that consists of a large number of low-cost passive reflecting elements. Moreover, each unit cell of RIS can independently induce the amplitude and phase variations of the incident signal [4], thus cooperatively achieving fine 3D reflection beamforming. In the existing literature about RIS-assisted FD communications, the authors of [5] studied the beamforming optimization for a RIS-assisted FD communication system, where the SI is assumed to follow Gaussian distribution. Also, the authors of [6] studied the spatially correlated RIS-assisted multiuser FD massive multi-input-multi-output (mMIMO) system, where the SI is independent and identically distributed. Although RIS is combined with FD in [5] and [6], how to use RIS to deal with the strong SI was not discussed. The authors of [7] proposed a RIS-assisted FD wireless communication system that increases the effective path of the desired signal. However, the self-interference cancellation (SIC) capability is relatively small, because of the high power differential between the desired and interference signals. A RIS-assisted FD system is studied in [8], which analyzes the effects of residual SI, self-reflections and interference from the RIS. Simulation results of [8] suggest that RIS can counter the effect of the residual SI and can achieve the same outage probability as that in HD communications if the number of RIS meta-atoms is enough. This suggests the feasibility of utilizing RIS for SIC in FD communications.

On the other hand, with regard to RIS-assisted broadband transmission systems, the authors of [9] considered the capacity maximization for broadband transmission in a general MIMO orthogonal frequency division multiplexing (OFDM) system under frequency-selective fading channels. In [10], RISs are used in unmanned aerial vehicle (UAV)-based orthogonal frequency division multiple access (OFDMA) communication systems to enhance sum-rate. With a RIS, the composite channel from the UAV to ground users experiences both frequency-selectivity and spatial-selectivity fading. Besides, a RIS-assisted multi-carrier MIMO wireless physical layer security communication system was investigated in [11], which consists of a legitimate transmitter, a legitimate receiver, a RIS node, and an eavesdropper. It can be observed that while RIS-assisted FD transmission and RIS-assisted broadband transmission have been studied, how to deal with the SI for RIS-assisted FD broadband transmission is not well discussed.

To achieve miniaturization and portability of RIS-assisted FD devices, RISs are desired to be deployed inside the devices. Similar studies have been conducted in the area of visible light communication (VLC). In VLC, RIS can be deployed inside devices to enhance their performance. For example, [12] depicts an indoor VLC system where RIS assists in directing the received light and concentrating its beam on the photodetector (PD). It functions as a filter that permits light signals of specific wavelengths to pass while impeding unwanted light, resulting in reduced interference. The authors of [13] proposed and demonstrated that deploying liquid crystal (LC)-based RIS as part of the VLC receiver can improve data rate. The purpose of LC-RIS is providing incident light steering and intensity amplification to improve the received signal strength and the corresponding achievable data rate. The indoor VLC system is composed of a VLC-enabled ceiling light emitting diode array and a user equipped with a nematic LC RIS-based VLC receiver. The feasibility of miniaturized RISs with similar size to the RIS in this paper has also been demonstrated in existing works. For examples, the authors of [14] proposed and demonstrated the use of a 6-by-8 unit metasurface to protect sensitive devices from large signals, while still allowing a communication channel for small signals. The authors of [15] fabricated a novel ultrathin linear-to-cross-polarization transmission converter based on a $80 \times 80 ~\rm mm^2$ metasurface (having $10 \times 10$ unit cells).

Inspired by the above works related to VLC where RISs can be deployed inside devices to enhance performance, in this paper we consider an FD broadband wireless communication system where small RISs are deployed inside FD devices to cancel SI. With the proposed design for the reflection coefficient (RC) matrix of the RIS, the SI can be significantly canceled, which promises the double data rate as compared with HD. The main contributions of this paper are summarized as follows:

1) To the best of our knowledge, this is the first work to study RIS-assisted FD-OFDM communication system where small RISs are deployed inside FD devices to mitigate the strong SI by passive beamforming. The system consists of two FD devices and each device is equipped with a single transmit antenna, a single receive antenna, and a RIS. The RIS-based SIC scheme developed in this paper is a new attempt of SIC in the propagation domain. Furthermore, the deployment of small RISs within communication terminals showcases a new application scenario for RIS-assisted wireless communications.

2) Since small RISs are deployed inside devices, it is essential to account for the near-field behavior of the RIS. RIS-assisted FD-OFDM system is accurately modeled by the near-field channel model, which ensures its effectiveness for broadband transmission in this scenario.

3) To enhance the performance of the new SIC scheme for broadband transmission, we formulate an optimization problem to maximize the SIC capability. Given the non-convexity of the optimization problem, an alternate optimization (AO) algorithm is developed to jointly optimize the power allocation vector and RC matrix in three cases. Specifically, for the fixed RC, the closed-form solution to power allocation is derived. For the fixed power allocation vector, quadratic transform, Karush-Kuhn-Tucker (KKT) conditions, Riemannian conjugate gradient (RCG) algorithm, and nearest point projection (NPP) method are adopted to optimize the RC matrix.

4) Finally, numerical results are presented to validate the performance of the proposed SIC scheme and the effectiveness of the RIS phase shift design. Numerical results demonstrate that the capacity gain of RIS-assisted FD-OFDM system over HD-OFDM system without RISs can be more than 2.25 times.


> **Fig. 1** — RIS-assisted FD-OFDM communication system.

The rest of the paper is organized as follows. Section II gives the system model for the proposed RIS-based SIC scheme and analyzes the near-field behavior of the RIS. In Section III, an optimization problem is formulated to maximize the SIC capability. Then we utilize AO algorithm to jointly optimize the power allocation vector and RC matrix in three cases, with the goal of minimizing residual SI. Simulation results are given in Section IV to verify the performance of the proposed SIC scheme. This paper concludes with Section V.

*Notations*: Boldface straight lowercase and uppercase letters denote vectors and matrices, respectively. $\mathbb{C}^{x \times y}$ denotes the space of $x\times y$ complex matrices, $\mathbb{R}^{x \times y}$ denotes the space of $x\times y$ real matrices, and $\max(x, y)$ denotes the maximum between two real numbers $x$ and $y$. For a matrix $\rm C$ of arbitrary size, $\boldsymbol{\rm C}^{\rm H}$, $\parallel\boldsymbol{\rm C}\parallel $, and $\boldsymbol{\rm C}^{\ast }$ denote the conjugate transposed matrix, the Frobenius norm, and the conjugate of $\boldsymbol{\rm C}$, respectively. Further, we use $\boldsymbol{\rm I}_{N}$ and $\boldsymbol{\rm 0}_{N}$ to denote an identity matrix and all-zero matrix of appropriate dimensions, respectively. $\triangleq$ and $\sim$ stands for "defined as" and "distributed as", respectively. $\bmod (\cdot, \cdot)$ denotes the modulo operation, $\left\lfloor \cdot \right \rfloor$ denotes round down, and $\odot$ denotes Hadamard product. The distribution of a circularly symmetric complex Gaussian (CSCG) random variable with mean $\mu $ and variance $\sigma^{2}$ is denoted by $\mathcal{CN}(\mu ,\sigma^{2})$. $\bf c\sim \mathcal{CN}(\mu ,\bf C)$ indicates a complex random vector $\bf c$ following the distribution of mean $\mu $ and covariance matrix $\bf C$. $\left|\cdot\right|$ denotes the absolute value operation, $\mathrm{tr}(\cdot)$ denotes the operation of trace, $\tan ^{-1}(\cdot)$ denotes the arctangent function, and $\rm{diag}\left(\mathbf{c}\right)$ denotes a square diagonal matrix with the elements of $\mathbf{c}$ on the main diagonal. $\arg (\cdot)$ and $\Re(\cdot)$ denote the angle and the real part of a complex number, respectively.

$$
\xi_{m,\mathbf{t}, \mathbf{p}_{m,n}}=\frac{1}{4 \pi} \sum_{x \in \mathcal{X}_{m,t, n}} \sum_{y \in \mathcal{Y}_{m,t, n}}\left(\frac{{x y}/{d^{2}}}{3\left({y^{2}}/{d^{2}}+1\right) \sqrt{{x^{2}}/{d^{2}}+{y^{2}}/{d^{2}}+1}}+\frac{2}{3} \tan ^{-1}\left(\frac{{x y}/{d^{2}}}{\sqrt{{x^{2}}/{d^{2}}+{y^{2}}/{d^{2}}+1}}\right)\right)
\tag{3}
$$


## II. System Model

As shown in Fig. 1, we consider an FD-OFDM communication system where two FD devices (denoted by $U_1$ and $U_2$) exchange information with each other under frequency-selective fading channels. Both FD devices have a single transmit and receive antenna. We assume that each device is equipped with a RIS which contains $N$ reflection elements to assist FD wireless communications. The RIS assists the FD device through its $N$ reflection elements which could control the amplitude and phase of the incident signal independently. The receive antenna receives not only the SI signal but also the reflected signal, which is utilized to diminish the SI signal. Thus, the SI can be significantly canceled.

The reconfigurability of RIS lies not only in the amplitude and phase, but also in frequency and polarization shifts [16]. In this paper, the RIS is deployed inside the device, and the positions of the transmit antenna, the receive antenna, and the RIS are fixed. While the RIS channel gain is not affected by the distance between the antennas and the RIS, this paper considers a wideband OFDM system where the RIS channel gain is also affected by the frequency. The RIS channel varies with the frequency, and if the bandwidth exceeds the available bandwidth, it is necessary to reconfigure the wireless environment to ensure the performance gain of the RIS, which reflects the reconfigurability of RIS [17].


> **Fig. 2** — The definition of near and far-field for a small antenna (a sphere with radius $a \ll \lambda$).

We consider the case where the operating frequency is $f=5.8$ GHz [18] and the wavelength is $\lambda=c/f=0.0517$ m. Also, RISs are considered small and deployed inside FD devices. The distance between the transmitter/receiver of each FD device and each unit cell of its equipped RIS is assumed to be larger than $0.16\lambda$ and less than $5\lambda$. According to the definition of the near-field and far-field [19] for the small-size antenna $S$ shown in Fig. 2, the transmitter/receiver of each FD device is in the radiating near-field of each unit cell of its equipped RIS. The near-field behavior and far-field behavior of the RIS are different. There are three differences between the near-field and the far-field [20]: the distance to each unit cell, the effective unit cell areas, and the loss from polarization mismatch. Considering the above three differences, in the following the near-field behavior of the RIS is analyzed and utilized to mitigate SI.


### II-A. Channel Model

Based on previous RIS-assisted FD-OFDM system model, the channel model is introduced in this subsection. We define the number of OFDM subcarriers as $M$ and the indexes of subcarriers are denoted by $\mathit m\in \mathcal{M} \triangleq\{0,1, \ldots, M-1\}$. Thus the subcarrier spacing $\Delta f=B/M$, where $B$ denotes the transmission bandwidth. We let $\mathit h_{m,\rm 1}$ and $\mathit g_{m,\rm 1}$ denote the SI channel gains of device $U_1$ and device $U_2$ on the $m$th subcarrier, respectively. The frequency-domain channel from transmit antenna $T_2$ to receive antenna $R_1$, from RIS $S_2$ to receive antenna $R_1$, and from transmit antenna $T_1$ to RIS $S_2$ on the $m$th subcarrier are denoted by $\mathit{h}_{m,\rm T2}$, $\mathbf {g}_{m,21} \in \mathbb{C}^{N \times 1}$, and $\mathbf{g}_{m,12} \in \mathbb{C}^{N \times 1}$, respectively. The frequency-domain channel from transmit antenna $T_1$ to receive antenna $R_2$, from RIS $S_1$ to receive antenna $R_2$, and from transmit antenna $T_2$ to RIS $S_1$ on the $m$th subcarrier are denoted by $\mathit {h}_{m,\rm T1}$, $\mathbf{h}_{m,12} \in \mathbb{C}^{N \times 1}$, and $\mathbf{h}_{m,21} \in \mathbb{C}^{N \times 1}$, respectively. The frequency-domain channel between transmit antenna $T_1$ and RIS $S_1$ on the $m$th subcarrier is denoted by $\mathbf{h}_{m,\rm I2} \in \mathbb{C}^{N \times 1}$ and that between receive antenna $R_1$ and RIS $S_1$ on the $m$th subcarrier is denoted by $\mathbf{h}_{m,\rm 1I} \in \mathbb{C}^{N \times 1}$. Similarly, the frequency-domain channel between transmit antenna $T_2$ and RIS $S_2$ on the $m$th subcarrier is denoted by $\mathbf{g}_{m,\rm I2} \in \mathbb{C}^{N \times 1}$ and that between receive antenna $R_2$ and RIS $S_2$ on the $m$th subcarrier is denoted by $\mathbf{g}_{m,\rm 1I} \in \mathbb{C}^{N \times 1}$. In this paper, we assume that both RISs only reflect once since the power of the signal reflected two or more times is much smaller than that of the signal reflected once [21], [22]. Moreover, the channel gains of $T_1$-$S_2$-$R_1$ link and $T_2$-$S_1$-$R_2$ link can be neglected due to the long distance [5], [6]. In this paper, we assume that wireless channels experience quasi-static block-fading and the channel state information (CSI) is known to FD [6], [23].

We set up a right-angle coordinate system for each FD device to compute the coordinate of the center of each unit cell and analyze the near-field channel of RIS. As shown in Fig. 3, the center of RIS is located at the coordinate origin of the XY-plane. Also, both the transmit antenna and the receive antenna are located in the XZ-plane and they are symmetric about the Z axis. The coordinates of the transmit and receive antenna are denoted by $\left(x_{t}, y_{t}, d\right)$ and $\left(-x_{t}, y_{t}, d\right)$, respectively. We consider the RIS is square where the cells are deployed edge-to-edge and each RIS unit cell has an area of $R_m$ on the $m$th subcarrier. If we number the unit cells from left to right, row by row, the coordinate of the center of the $n$th unit cell on the $m$th subcarrier is $\left(x_{m,n}, y_{m,n}, 0\right)$ with

$$
x_{m,n}=-\frac{(\sqrt{N}-1) \sqrt{R_m}}{2}+\sqrt{R_m} \mathrm {mod} (n-1, \sqrt{N})
\tag{1}
$$

and

$$
y_{m,n}=\frac{(\sqrt{N}-1) \sqrt{R_m}}{2}-\sqrt{R_m}\left\lfloor \frac{n-1}{\sqrt{N}}  \right \rfloor.
\tag{2}
$$

We denote by $\mathbf{Q}_m \in \{ {\it h}_{m,1},{\it g}_{m,1},\mathbf{g}_{m,\rm I2},\mathbf{g}_{m,\rm 1I},\mathbf{h}_{m,\rm I2},\mathbf{h}_{m,\rm 1I}\}$ the near-field channel on the $m$th subcarrier where $\mathit m\in \mathcal{M}$ and use an exact model, which takes into account the near-field behavior of the RIS, to quantify it [24], [25]. We consider that the transmit antenna located at $\bf{t}=(\it x_t,\it y_t,\it d)$ is lossless isotropic and transmits a signal that has polarization in the Y direction when traveling in the Z direction. The channel amplitude gain on the $m$th subcarrier $\xi_{m,\mathbf t,\mathbf{p}_{m,n}}$ at the $n$th unit cell , located at $\mathbf{p}_{m,n} = (x_{m,n}, y_{m,n}, 0)$, can be given by (3) at bottom of this page, where

$$
\mathcal{X}_{m,t, n} =\left\{\sqrt{R_m} / 2+x_{m,n}-x_{t}, \sqrt{R_m} / 2-x_{m,n}+x_{t}\right\}
\tag{4}
$$

and

$$
\mathcal{Y}_{m,t, n} =\left\{\sqrt{R_m} / 2+y_{m,n}-y_{t}, \sqrt{R_m} / 2-y_{m,n}+y_{t}\right\}.
\tag{5}
$$


> **Fig. 3** — Right-angle coordinate system for each FD device.

Based on (3), (4), and (5), the channel gain on the $m$th subcarrier between the transmit antenna and the RIS can be given by

$$
\mathbf{Q}_m= \left[\it {\varsigma}_{m,\rm 1}, \cdots, \it {\varsigma}_{m,N}\right]^{\mathrm{T}},
\tag{6}
$$

where $\mathbf{Q}_m \in \{ \mathbf{g}_{m,\rm I2},\mathbf{g}_{m,\rm 1I},\mathbf{h}_{m,\rm I2},\mathbf{h}_{m,\rm 1I}\}$ and $ \varsigma_{m,n}=\left | \varsigma_{m,n} \right |e^{-j \vartheta_{m,n}}$ with

$$
{\left |\varsigma_{m,n}\right|}^2 =\xi_{m,\mathbf{t}, \mathbf{p}_{m,n}}
\tag{7}
$$

and

$$
\vartheta_{m,n} =2 \pi \bmod \left(\frac{\left \| \mathbf {t}-\mathbf{p}_{m,n} \right \| }{\lambda_m}, 1\right).
\tag{8}
$$

In (8), $\lambda_m=c/f_m$ is the wavelength of the $m$-th subcarrier with the frequency of

$$
f_m=f-B/2+m\Delta f.
\tag{9}
$$

Similarly, we can also obtain the channel gain on the $m$th subcarrier between the RIS and the receive antenna using the above model. Since the transmit and receive antenna coordinates are fixed, the modulus of the SI channel gain remains constant under different subcarriers. However, the phase of the SI channel gain varies under different subcarriers. The expression for the near-field channel gain of RIS provided in this paper is derived by treating each RIS unit cell as a receive antenna [24], [25]. Thus, when calculating the SI gain between the transmit and receive antenna, we can consider the receive antenna as a RIS which has only one unit cell. Following similar steps, the SI channel gain on the $m$th subcarrier between the transmit antenna and the receive antenna of each FD device can be expressed as follows:

$$
\mathbf{Q}_m=\sqrt{\xi_{\mathbf t,\mathbf{p}_{\rm r}}} e^{-j \vartheta_{m,\rm r}},
\tag{10}
$$

where $\mathbf{Q}_m \in \{ {\it h}_{m,1},{\it g}_{m,1} \}$. The coefficients $\xi_{\mathbf t,\mathbf{p}_{\rm r}}$ and $\vartheta_{m,\rm r}$ in (10) can be equivalently calculated based on (3), (4), (5) and (8) with $\mathbf{p}_{\rm r} = (x_t, y_t, 0)$ and $d=2x_t$. Note that the employed channel model is applicable to the radiating near-field, but not to the reactive near-field [24], [25]. We assume that the transmitter/receiver of each FD device is in the radiating near-field of each unit cell of its equipped RIS, such that the channel model is accurate.

The far-field channel on the $m$th subcarrier is denoted by $\mathbf{\Gamma }_m \in \{\mathit{h}_{m,\rm T1},\mathit{h}_{m,\rm T2},\mathbf{g}_{m,12},\mathbf{g}_{m,21},\mathbf{h}_{m,12},\mathbf{h}_{m,21}\}$, then we model it with Rician fading. For a Rician channel with K-factor denoted by $K_{\rm r}$, the channel matrix $\boldsymbol{\rm \Upsilon }$ can be given as follows:

$$
\mathbf{\Upsilon}=\sqrt{L}\left(\sqrt{\frac{K_{\rm r}}{1+K_{\rm r}}}\boldsymbol{\rm \Upsilon  }^{\rm LOS}+\sqrt{\frac{1}{1+K_{\rm r}}}\boldsymbol{\rm \Upsilon  }^{\rm NLOS}\right),
\tag{11}
$$

where $\boldsymbol{\rm \Upsilon }^{\rm NLOS}$ denotes a large number of secondary non-light of sight (NLOS) channel gains, $\boldsymbol{\rm \Upsilon }^{\rm LOS}$ denotes the normalized complex light of sight (LOS) channel gains between the transceiver antennas, and $L$ denotes the corresponding pathloss. We can obtain the far-field channel on the $m$th subcarrier $\mathbf{\Gamma }_m$ from the following equation

$$
\mathbf{\Gamma }_m= \mathbf{\Upsilon}\boldsymbol{f}_{m}^{\mathrm{H}},
\tag{12}
$$

where $\boldsymbol{f}_{m}^{\mathrm{H}}$ denotes the $m$th column of the $M \times M$ discrete Fourier transform (DFT) matrix $\boldsymbol{F}_{M}$.


### II-B. Signal Model

Without loss of generality, in the following we only analyze the transmission from $U_2$ to $U_1$ with the assistance of $S_1$ and $S_2$. The presented analyses and scheme can be extended for the transmission from $U_1$ to $U_2$ with the assistance of $S_1$ and $S_2$ in a straightforward manner. We denote by $\mathbf{x}_1 \triangleq\left[X_{1,0},\ldots, X_{1,m}, \ldots, X_{1,M-1}\right]^{T}$ and $\mathbf{x}_2 \triangleq\left[X_{2,0},\ldots, X_{2,m}, \ldots, X_{2,M-1}\right]^{T}$the OFDM symbol transmitted from transmit antenna $T_1$ and that from transmit antenna $T_2$, respectively, where $X_{1,m}$ and $X_{2,m}$ are the OFDM symbols on the $m$th subcarrier. These OFDM symbols are first transformed into the time domain via an $M$-point inverse discrete Fourier transform (IDFT), and then appended by a cyclic prefix (CP) of length $M_{\rm cp}$. We assume that the length of CP is longer than the maximum delay spread of all channels, denoted by $L_{\rm max}$, to eliminate the inter-symbol interference (ISI). Moreover, let $ \mathbf{p}_1= \left[p_{1,0}, \ldots,p_{1,m}, \ldots, p_{1,M-1}\right]^{T} \in \mathbb{R}^{M \times 1}$ and $ \mathbf{p}_2= \left[p_{2,0}, \ldots,p_{2,m}, \ldots, p_{2,M-1}\right]^{T} \in \mathbb{R}^{M \times 1}$ where $p_{1,m} \ge 0$, $p_{2,m} \ge 0$ denote the power allocated to the $m$th subcarrier of $U_1$ and $U_2$, respectively. Assume the transmit power constraint at $U_1$ is $P_1$ and the transmit power constraint at $U_2$ is $P_2$. Thus the power allocation at $U_1$ and $U_2$ should satisfy $\sum_{m=0}^{M-1} p_{1,m} \leq P_1$ and $\sum_{m=0}^{M-1} p_{2,m} \leq P_2$, respectively. In fact, when we design phase shift control circuits, RIS can only bring the same phase shift on different subcarriers. Thus we model the RC matrix of RIS $S_1$ as $\bf{\Phi}=\sqrt{\eta} \rm{diag}\left(\rm{\phi}_{1}, \cdots, \phi_\mathit{n}, \cdots, {\phi}_\mathit{N}\right)$, where $\eta\le 1$ is the reflection efficiency and $\mathrm{\phi}_\mathit{n}$ with $\mathit n\in \mathcal{N} \triangleq\{1,2, \ldots, N\}$ is the RC of the $n$th unit cell of RIS $S_1$. In the same way, we model the RC matrix of RIS $S_2$ as $\bf{\Psi}=\sqrt{\beta } \rm{diag}\left( \psi _{1}, \cdots, \psi_\mathit{n}, \cdots, \rm \psi _\mathit{N}\right)$, where $\beta \le 1$ is the reflection efficiency and $\rm \psi_\mathit{n}$ with $\mathit n\in \mathcal{N}$ is the RC of the $n$th unit cell of RIS $S_2$. Considering the practical implementation of the RIS, we assume that the feasible set of RC $\rm {\varphi}_\mathit{n}\in \{ \phi_\mathit{n}, \psi_\mathit{n} \}$ has the following three cases:

1) Both the amplitude and phase of each RIS unit cell can be controlled independently and continuously [22], [26], i.e.,

$$
\rm \varphi _\mathit{n} \in \mathcal{F}_{1} \triangleq\left\{\rm \varphi _\mathit{n}\Big|\big| \rm \varphi _\mathit{n}\big|^{2} \leq 1\right\},
\tag{13}
$$

so the theoretical upper bound of passive beamforming performance can be achieved under this assumption.

2) The phase of each RIS unit cell can be controlled independently, while the amplitude is fixed to one [22], [27], i.e.,

$$
\varphi_\mathit{n} \in \mathcal{F}_{2} \triangleq\left\{ \varphi_\mathit{n}\Big|\big|  \varphi_\mathit{n}\big|^{2}=1\right\}.
\tag{14}
$$

3) The RC of each RIS unit cell can only take $\tau$ discrete values and these discrete values are equally spaced on the unit circle [28], [29], i.e.,

$$
\begin{aligned}
\rm \varphi_\mathit{n} \in \mathcal{F}_{3} \triangleq\Bigg\{\rm \varphi_\mathit{n}  \Bigg| \rm \varphi_\mathit{n}=e^{j \rm \theta_\mathit{n}},\\
\theta_{n} \in\left\{0, \frac{2 \pi}{\tau}, \cdots, \frac{2 \pi(\tau-1)}{\tau}\right\}\Bigg\}.
\end{aligned}
\tag{15}
$$

By analyzing the three cases of the RIS, we can comprehensively understand the characteristics and performances of RIS-assisted FD-OFDM communication system [22]. The continuous and discrete phases case have lower manufacturing complexity compared to the ideal phases case which requires simultaneous adjustment of both phase and amplitude. This can ultimately provide a better guidance and support for practical applications.

After removing CP and performing $M$-point DFT, the received signal on the $m$th subcarrier at the receiver of device $U_1$ is expressed as follows:

$$
\begin{aligned}
Y_{1,m}=\left(\mathit{h}_{m,\rm T2}+{\mathbf{h}_{m,\rm 1I}^{\mathrm{H}}} \boldsymbol{\Phi} \mathbf{h}_{m,21}+{\mathbf{g}_{m,21}^{\mathrm{H}}} \boldsymbol{\Psi} \mathbf{g}_{m,\rm I2}\right)X_{2,m} \\ +\left(\mathit{h}_{m,1}+{\mathbf{h}_{m,\rm 1I}^{\mathrm{H}} } \boldsymbol{\Phi} \mathbf{h}_{m,\rm I2}\right) X_{1,m}+\mathit{Z}_{1,m},
\end{aligned}
\tag{16}
$$

where $\mathit{Z}_{1,m}\sim \mathcal{CN}(0,\sigma_{1}^{2})$ is the additive white Gaussian noise (AWGN) on the $m$th subcarrier.

After simplification, (16) can be re-written as follows:

$$
\begin{aligned}
Y_{1,m}=\left(\mathit{h}_{m,\rm T2}+{\mathbf{h}_{m,\rm I}^{\mathrm{H}}} \boldsymbol{\phi} +{\mathbf{g}_{m,\rm I}^{\mathrm{H}}} \boldsymbol{\psi} \right)X_{2,m} \\ +\left(\mathit{h}_{m,1}+{\mathbf{h}_{m,\rm R}^{\mathrm{H}} } \boldsymbol{\phi} \right) X_{1,m}+\mathit{Z}_{1,m},
\end{aligned}
\tag{17}
$$

where $\mathbf{h}_{m,\rm I}=\sqrt{\eta}\left(\mathbf{h}_{m,\rm 1I} \odot \mathbf{h}_{m,\rm 21}^{*}\right)$ with $\mathbf{h}_{m,\rm I} \in \mathbb{C}^{N \times 1}$, $\mathbf{g}_{m,\rm I}=\sqrt{\beta}\left(\mathbf{g}_{m,\rm 21} \odot \mathbf{g}_{m,\rm I2}^{*}\right)$ with $\mathbf{g}_{m,\rm I} \in \mathbb{C}^{N \times 1}$, and $\mathbf{h}_{m,\rm R}=\sqrt{\eta}\left(\mathbf{h}_{m,\rm 1I} \odot \mathbf{h}_{m,\rm I2}^{*}\right)$ with $\mathbf{h}_{m,\rm R} \in \mathbb{C}^{N \times 1}$. Moreover, $\boldsymbol{\phi}=\left[\phi_{1}, \cdots, \phi_{n}, \cdots, \phi_{N}\right]^{\mathrm{T}}$ and $\boldsymbol{\psi}=\left[\psi_{1}, \cdots, \psi_{n} \cdots, \psi_{N}\right]^{\mathrm{T}}$ denote the RC vector of RIS $S_1$ and RIS $S_2$, respectively. We define $\mathbf{y}_1 \triangleq\left[Y_{1,0}, \cdots, Y_{1,m}, \cdots, Y_{1,M-1}\right]^{\mathrm{T}}$ and the received OFDM symbol at the receiver of device $U_1$ can be re-written as follows:

$$
\begin{aligned}
\mathbf{y}_1=\mathbf{X}_{2} \left(\mathbf{h}_{\rm T,2}+{\mathbf{H}_{\rm I}} \boldsymbol{\phi} +{\mathbf{G}_{\rm I}} \boldsymbol{\psi} \right) \\ +\mathbf{X}_{1}\left(\mathbf{h}_{1}+{\mathbf{H}_{\rm R}} \boldsymbol{\phi} \right) +\mathbf{z}_{1},
\end{aligned}
\tag{18}
$$

where $\mathbf{h}_{\rm T,2}=\left[\mathit{h}_{0,\rm T2}, \cdots, \mathit{h}_{m,\rm T2}, \cdots, \mathit{h}_{M-1,\rm T2}\right]^{\mathrm{T}}\in \mathbb{C}^{M \times 1}$ is the channel frequency response (CFR) of $T_2$-$R_1$ link, $\mathbf{h}_{\rm 1}=\left[\mathit{h}_{0,\rm 1}, \cdots, \mathit{h}_{m,\rm 1}, \cdots, \mathit{h}_{M-1,\rm 1}\right]^{\mathrm{T}}\in \mathbb{C}^{M \times 1}$ is the CFR of SI channel, $\mathbf{H}_{\rm I}\boldsymbol{\phi}$ with $\mathbf{H}_{\rm I}=\left[\mathit{h}_{0,\rm I}^{\mathrm{H}}, \cdots, \mathit{h}_{m,\rm I}^{\mathrm{H}}, \cdots, \mathit{h}_{M-1,\rm I}^{\mathrm{H}}\right]^{\mathrm{T}}\in \mathbb{C}^{M \times N}$ is the equivalent cascaded CFR of $T_2$-$S_1$-$R_1$ link, $\mathbf{G}_{\rm I} \boldsymbol{\psi}$ with $\mathbf{G}_{\rm I}=\left[\mathit{g}_{0,\rm I}^{\mathrm{H}}, \cdots, \mathit{g}_{m,\rm I}^{\mathrm{H}}, \cdots, \mathit{g}_{M-1,\rm I}^{\mathrm{H}}\right]^{\mathrm{T}}\in \mathbb{C}^{M \times N}$ is the equivalent cascaded CFR of $T_2$-$S_2$-$R_1$ link, and ${\mathbf{H}_{\rm R}} \boldsymbol{\phi}$ with $\mathbf{H}_{\rm R}=\left[\mathit{h}_{0,\rm R}^{\mathrm{H}}, \cdots, \mathit{h}_{m,\rm R}^{\mathrm{H}}, \cdots, \mathit{h}_{M-1,\rm I}^{\mathrm{H}}\right]^{\mathrm{T}}\in \mathbb{C}^{M \times N}$ is the equivalent cascaded CFR of $T_1$-$S_1$-$R_1$ link. $\mathbf{X}_{2}=\rm{diag}\left(\mathbf{x}_2\right)$ and $\mathbf{X}_{1}=\rm{diag}\left(\mathbf{x}_1\right)$ denote the diagonal matrix of OFDM symbol $\mathbf{x}_2$ and OFDM symbol $\mathbf{x}_1$, respectively. Moreover, $\mathbf{z}_1 =\left[Z_{1,0}, \cdots, Z_{1,m}, \cdots, Z_{1,M-1}\right]^{\mathrm{T}}$ denotes the AWGN vector at $U_1$, which follows $\mathcal{CN}(0,\sigma_{1}^{2}\rm {I}_\mathit {M})$. In addition, $\mathbf{X}_{2} \left(\mathbf{h}_{\rm T,2}+{\mathbf{H}_{\rm I}} \boldsymbol{\phi} +{\mathbf{G}_{\rm I}} \boldsymbol{\psi} \right)$ represents the desired signal, $\mathbf{X}_{1}\mathbf{h}_{1}$ is the SI, and $\mathbf{X}_{1}{\mathbf{H}_{\rm R}} \boldsymbol{\phi}$ is the RIS-assisted signal to cancel the severe SI. The SIC performance can be measured by the SIC capability $\Lambda $ (dB) [30], which is defined as follows:

$$
\Lambda=10 \log _{10} \frac{E_{0}+E_{N}}{E_{c}+E_{N}},
\tag{19}
$$

where $E_{0}$ is the energy of the SI signal before SIC, $E_{c}$ is the energy of the residual SI after SIC, and $E_{N}$ is the energy of noise.

Substituting Eq. (17) into Eq. (19), we have the SIC capability of RIS-assisted FD-OFDM communications as follows:

$$
\Lambda=10 \log _{10} \sum_{m=0}^{M-1}{\frac{\left|\mathit{h}_{m,1}\right|^{2} p_{1,m}+\sigma_{1}^{2}}{\left|\mathit{h}_{m,1}+{\mathbf{h}_{m,\rm R}^{\mathrm{H}} } \boldsymbol{\phi}\right|^{2} p_{1,m}+\sigma_{1}^{2}}} .
\tag{20}
$$

Furthermore, the system capacity after SIC can be expressed as follows:

$$
\begin{aligned}
C_{\rm FD}=\frac{1}{M+M_{cp}} \sum_{m=0}^{M-1} \mathrm{\log} _{2}\left(1+\right.\\
\left.\frac{\left|\mathit{h}_{m,\rm T2}+{\mathbf{h}_{m,\rm I}^{\mathrm{H}}} \boldsymbol{\phi} +{\mathbf{g}_{m,\rm I}^{\mathrm{H}}} \boldsymbol{\psi}\right|^{2} p_{2,m}}{\left|\mathit{h}_{m,1}+{\mathbf{h}_{m,\rm R}^{\mathrm{H}} } \boldsymbol{\phi}\right|^{2} p_{1,m}+\sigma_{1}^{2}}\right).
\end{aligned}
\tag{21}
$$

Given the same bandwidth, the capacity of HD-OFDM communication system without RIS-based SIC can be given by

$$
C_{\rm HD}=\frac{1}{2} \frac{1}{M+M_{cp}} \sum_{m=0}^{M-1} \log _{2}\left(1+\frac{\left|\mathit{h}_{m,\rm T2}\right|^{2} p_{2,m}}{\sigma_{1}^{2}}\right).
\tag{22}
$$


## III. SIC Capability Maximization Via Joint Power Allocation And Reflection Coefficient Optimization

In this section, the RC matrix of the RIS and power allocation scheme of each device are jointly optimized to maximize the SIC capability shown in (20). We first formulate the optimization problem and then propose an AO algorithm to solve it.


### III-A. Problem Formulation

Considering the constraints of the transmit power and the RC, the SIC capability maximization problem is formulated as follows:

$$
\text { (P1) }\quad  \max _{\mathbf p_{1}, \boldsymbol{\phi}} \quad\sum_{m=0}^{M-1}{\frac{\left|\mathit{h}_{m,1}\right|^{2} p_{1,m}+\sigma_{1}^{2}}{\left|\mathit{h}_{m,1}+{\mathbf{h}_{m,\rm R}^{\mathrm{H}} } \boldsymbol{\phi}\right|^{2} p_{1,m}+\sigma_{1}^{2}}}
\tag{23a}
$$

$$
\text { s.t.:} \quad  1). \quad\sum_{m=0}^{M-1} p_{1,m} \leq P_1,
\tag{23b}
$$

$$
\quad  2).\quad p_{1,m}\ge 0, \quad \forall \mathit m\in \mathcal{M},
\tag{23c}
$$

$$
\quad  3). \quad\phi_{n} \in \mathcal{F}, \quad \forall \mathit n\in \mathcal{N},
\tag{23d}
$$

where $\mathcal{F}$ is chosen from $\mathcal{F}_1$, $\mathcal{F}_2$, and $\mathcal{F}_3$. If $\mathrm{\phi}_{n} \in \mathcal{F}_{2}$ or $\mathrm{\phi}_{n} \in \mathcal{F}_{3}$, constraint (23d) is non-convex. Moreover, the objective function of (P1) is non-convex. Thus, (P1) is a non-convex problem and is difficult to solve directly. To overcome the above challenges, in the following we propose an AO algorithm which optimizes $\mathbf p_{1}$ and $\boldsymbol{\phi}$ iteratively to find an approximate solution to (P1).


### III-B. Power Allocation Optimization with Given Reflection Coefficient

In this subsection, we optimize power allocation vector for the given RC vector. Due to the fixed RC vector, the superimposed CFR $\mathit{h}_{m,1}+{\mathbf{h}_{m,\rm R}^{\mathrm{H}} } \boldsymbol{\phi}$ is fixed, then problem (P1) can be transformed into

$$
\text { (P2) }\quad  \max _{\mathbf p_{1}} \quad\sum_{m=0}^{M-1}{\frac{\mathit{b}_{m} p_{1,m}+\sigma_{1}^{2}}{\mathit{v}_{m}  p_{1,m}+\sigma_{1}^{2}}}
\tag{24a}
$$

$$
\text { s.t.:} \quad  1). \quad\sum_{m=0}^{M-1} p_{1,m} \leq P_1,
\tag{24b}
$$

$$
\quad  2).\quad p_{1,m}\ge 0, \quad \forall \mathit m\in \mathcal{M},
\tag{24c}
$$

where $\mathit{b}_{m}=\left|\mathit{h}_{m,1}\right|^{2}$, $\mathit{v}_{m}=\left|\mathit{h}_{m,1}+{\mathbf{h}_{m,\rm R}^{\mathrm{H}} } \boldsymbol{\phi}\right|^{2}$, and constraint (23d) is omitted because $\boldsymbol{\phi}$ is fixed. Note that (P2) is a multiple-ratio fractional programming (FP) problem which is difficult to solve, thus we use the quadratic transform [31] to transform (P2) into the following problem

$$
\text { (P3) }  \max _{\mathbf p_{1},\mathbf q} \sum_{m=0}^{M-1}\left({2\mathit{q}_{m}\sqrt{\mathit{b}_{m} p_{1,m}+\sigma_{1}^{2}}-\mathit{q}_{m}^{2}\left(\mathit{v}_{m}  p_{1,m}+\sigma_{1}^{2}\right)}\right)
\tag{25a}
$$

$$
\quad\text { s.t.:} \quad  1). \quad\sum_{m=0}^{M-1} p_{1,m} \leq P_1,
\tag{25b}
$$

$$
\quad  2).\quad p_{1,m}\ge 0, \quad \forall \mathit m\in \mathcal{M},
\tag{25c}
$$

$$
\quad  3).\quad q_{m}\in \mathbb{R}, \quad \forall \mathit m\in \mathcal{M},
\tag{25d}
$$

where $\mathbf{q}=\left[\mathit{q}_{0}, \cdots, \mathit{q}_{m}, \cdots, \mathit{q}_{M-1}\right]^{\mathrm{T}}$ includes the introduced auxiliary variables $\mathit{q}_{0}, \cdots, \mathit{q}_{m}, \cdots, \mathit{q}_{M-1}$. When the power allocation vector $\mathbf p_{1}$ is fixed, the closed-form solution to $\mathbf{q}$ can be derived as follows:

$$
\ddot{\mathit{q}}_{m}=\frac{\sqrt{\mathit{b}_{m} p_{1,m}+\sigma_{1}^{2}}}{\mathit{v}_{m}  p_{1,m}+\sigma_{1}^{2}},\quad \forall \mathit m\in \mathcal{M}.
\tag{26}
$$

When $\mathbf{q}$ is fixed, (P3) can be simplified to

$$
\text { (P3') } \! \max _{\mathbf p_{1}} \!\sum_{m=0}^{M-1}\!\left({2\mathit{q}_{m}\sqrt{\mathit{b}_{m} p_{1,m}\!+\sigma_{1}^{2}}-\mathit{q}_{m}^{2}\left(\mathit{v}_{m}  p_{1,m}\!+\sigma_{1}^{2}\right)}\right)
\tag{27a}
$$

$$
\quad\text { s.t.:} \quad  1). \quad\sum_{m=0}^{M-1} p_{1,m} \leq P_1,
\tag{27b}
$$

$$
\quad  2).\quad p_{1,m}\ge 0, \quad \forall \mathit m\in \mathcal{M}
\tag{27c}
$$

Notice that (27a) is concave with respect to $\mathbf p_{1}$, thus (P3') is a convex problem which can be solved with KKT conditions [32]. We can write the Lagrangian function corresponding to (P3') as follows:

$$
\begin{aligned}
L(\boldsymbol{\mathbf p_{1}},\lambda_{1}, \boldsymbol{\lambda}_2)=F(\mathbf p_{1})+\lambda_{1}\left(P_1-\sum_{m=0}^{M-1} p_{1,m}\right)\\+\sum_{m=0}^{M-1} \lambda_{2,m}p_{1,m},
\end{aligned}
\tag{28}
$$

where

$$
F(\mathbf p_{1})=\sum_{m=0}^{M-1}\left({2\mathit{q}_{m}\sqrt{\mathit{b}_{m} p_{1,m}+\sigma_{1}^{2}}-\mathit{q}_{m}^{2}\left(\mathit{v}_{m}  p_{1,m}+\sigma_{1}^{2}\right)}\right),
\tag{29}
$$

$\boldsymbol{\lambda}_2= \left[\lambda_{2,0}, \ldots, \lambda_{2,M-1}\right]$ with $\lambda_{2,m}\ge0,\forall \mathit m\in \mathcal{M}$ is the Lagrange multiplier vector, and $\lambda_1\ge0$ is the Lagrange multiplier. According to KKT conditions, we have

$$
\begin{cases}
 \displaystyle\frac{\mathit{q}_{m}\mathit{b}_{m}}{\sqrt{\mathit{b}_{m} p_{1,m}+\sigma_{1}^{2}}} -\mathit{q}_{m}^{2}\mathit{v}_{m} -\lambda_{1}-\lambda_{2,m}=0, \quad \forall \mathit m\in \mathcal{M},\\
\lambda_{1}\left(P_1-\sum_{m=0}^{M-1} p_{1,m}\right) = 0, \quad  \\
\lambda_{2,m}p_{1,m}=0,\quad \forall \mathit{m} \in \mathcal{M},\quad  \\
P_1-\sum_{m=0}^{M-1} p_{1,m}\ge 0,\quad  \\
p_{1,m}\ge 0, \quad \forall \mathit m\in \mathcal{M}.
\end{cases}
\tag{30}
$$

Solving (30), the closed-form solution to (P3') can be directly derived as follows:

$$
\ddot{\mathit{p}}_{1,m}=\max \left({a}_{m}-\frac{\sigma_{1}^{2}}{\it{ b}_{m}} ,0\right),\quad \forall \mathit m\in \mathcal{M},
\tag{31}
$$

where

$$
\mathit{a}_{m}= \frac{\mathit{q}_{m}^{2}\mathit{b}_{m}}{\left(\lambda_{1}+\mathit{q}_{m}^{2}\mathit{v}_{m}\right)^{2}} ,\quad \forall \mathit m\in \mathcal{M}
\tag{32}
$$

should be chosen to satisfy $\sum_{m=0}^{M-1} p_{1,m} = P_1$. The optimal solution to $\lambda_{1}$ and $\boldsymbol{\lambda}_2$ can be found by sub-gradient method or ellipsoid method [32].


### III-C. Reflection Coefficient Optimization with Given Power Allocation

For the given multi-carrier power allocation, the optimization of the RC in three cases is discussed in this subsection. We only show the optimization steps for RC vector $\boldsymbol{\phi}$. RC vector $\boldsymbol{\psi}$ can be optimized in the same manner. Due to the fixed power allocation vector $\mathbf p_{1}$, (P1) can be simplified as follows:

$$
\text { (P4) }\quad  \max _{ \boldsymbol{\phi}} \quad\sum_{m=0}^{M-1}{\frac{\left|\mathit{h}_{m,1}\right|^{2} p_{1,m}+\sigma_{1}^{2}}{\left|\mathit{h}_{m,1}+{\mathbf{h}_{m,\rm R}^{\mathrm{H}} } \boldsymbol{\phi}\right|^{2} p_{1,m}+\sigma_{1}^{2}}}
\tag{33a}
$$

$$
\text { s.t.:} \quad  1).  \quad\phi_{n} \in \mathcal{F}, \quad \forall \mathit n\in \mathcal{N},
\tag{33b}
$$

where constraints (23b) and (23c) are omitted because of the fixed power allocation vector $\mathbf p_{1}$. Notice that, similar to the previous subsection, (P4) is a multiple-ratio FP problem. Similarly, we introduce $\mathbf{l}=\left[\mathit{l}_{0}, \cdots, \mathit{l}_{m}, \cdots, \mathit{l}_{M-1}\right]^{\mathrm{T}}$, which includes the introduced auxiliary variables $\mathit{l}_{0}, \cdots, \mathit{l}_{m}, \cdots, \mathit{l}_{M-1}$ and then use the quadratic transform to transform (P4) into the following problem

$$
\text { (P5) } \quad   \max _{\boldsymbol{\phi},\mathbf l} \quad  \mathit{g}\left(\boldsymbol{\phi},\mathbf l\right)
\tag{34a}
$$

$$
\quad\text { s.t.:} \quad  1). \quad\phi_{n} \in \mathcal{F}, \quad \forall \mathit n\in \mathcal{N},
\tag{34b}
$$

$$
\quad  2). \quad l_{m}\in \mathbb{R}, \quad \forall \mathit m\in \mathcal{M},
\tag{34c}
$$

where

$$
\begin{aligned}
\mathit{g}\left(\boldsymbol{\phi},\mathbf l\right)=\sum_{m=0}^{M-1}\left(2\mathit{l}_{m}\sqrt{\left|\mathit{h}_{m,1}\right|^{2} p_{1,m}+\sigma_{1}^{2}}\right.\\ \left.-\mathit{l}_{m}^{2}\left(\left|\mathit{h}_{m,1}+{\mathbf{h}_{m,\rm R}^{\mathrm{H}} } \boldsymbol{\phi}\right|^{2} p_{1,m}+\sigma_{1}^{2}\right)\right).
\end{aligned}
\tag{35}
$$

When $\boldsymbol{\phi}$ is fixed, the closed-form solution to $\mathbf{l}$ can be found as follows:

$$
\ddot{\mathit{l}}_{m}=\frac{\sqrt{\left|\mathit{h}_{m,1}\right|^{2} p_{1,m}+\sigma_{1}^{2}}}{\left|\mathit{h}_{m,1}+{\mathbf{h}_{m,\rm R}^{\mathrm{H}} } \boldsymbol{\phi}\right|^{2} p_{1,m}+\sigma_{1}^{2}},\quad \forall \mathit m\in \mathcal{M}.
\tag{36}
$$

Because of the fixed $\mathbf{l}$ and $\mathbf p_{1}$, maximizing $\mathit{g}\left(\boldsymbol{\phi},\mathbf l\right)$ is equivalent to minimizing $\sum_{m=0}^{M-1}\left(\mathit{l}_{m}^{2}\left|\mathit{h}_{m,1}+{\mathbf{h}_{m,\rm R}^{\mathrm{H}} } \boldsymbol{\phi}\right|^{2} p_{1,m} \right)$. We first omit irrelevant items and then transform (P5) into

$$
\text { (P6) } \quad   \min _{\boldsymbol{\phi}} \quad  \bar{\mathit{g}}\left(\boldsymbol{\phi}\right)
\tag{37a}
$$

$$
\quad\text { s.t.:} \quad  \phi_{n} \in \mathcal{F}, \quad \forall \mathit n\in \mathcal{N},
\tag{37b}
$$

where

$$
\begin{aligned}
\bar{\mathit{g}}\left(\boldsymbol{\phi}\right)\\ \!=
\!\!\!\sum_{m=0}^{M-1}\!\!\left(\!\mathit{l}_{m}^{2} p_{1,m}\!\left(\!{\mathbf{h}_{m,\rm R}^{\mathrm{H}} } \boldsymbol{\phi}\mathit{h}_{m,1}^{\ast }\!+\!\boldsymbol{\phi}^{\mathrm{H}}\mathbf{h}_{m,\rm R}\mathit{h}_{m,1}\!\!+\!\boldsymbol{\phi}^{\mathrm{H}}\mathbf{h}_{m,\rm R}\mathbf{h}_{m,\rm R}^{\mathrm{H}} \boldsymbol{\phi}\!\right)\!\!\right)\\
 =\mathbf{w}\boldsymbol{\phi}+\boldsymbol{\phi}^{\mathrm{H}}\mathbf{c}+\boldsymbol{\phi}^{\mathrm{H}}\mathbf{A}\boldsymbol{\phi}
\end{aligned}
\tag{38}
$$

with

$$
\mathbf{w}=\sum_{m=0}^{M-1}\left(\mathit{l}_{m}^{2} p_{1,m}\mathit{h}_{m,1}^{\ast }\mathbf{h}_{m,\rm R}^{\mathrm{H}}\right),
\tag{39}
$$

$$
\mathbf{c}=\sum_{m=0}^{M-1}\left(\mathbf{h}_{m,\rm R}\mathit{l}_{m}^{2} p_{1,m}\mathit{h}_{m,1}\right),
\tag{40}
$$

and

$$
\mathbf{A}=\sum_{m=0}^{M-1}\left(\mathit{l}_{m}^{2} p_{1,m}\mathbf{h}_{m,\rm R}\mathbf{h}_{m,\rm R}^{\mathrm{H}}\right).
\tag{41}
$$

Notice that (38) is a quadratic convex function with respect to $\boldsymbol{\phi}$. Thus, (P6) is a quadratically constrained quadratic programming (QCQP). If $\mathrm{\phi}_{n} \in \mathcal{F}_{1}$, (P6) is a convex QCQP and its closed-form solution can be directly obtained using convex optimization tools. If $\mathrm{\phi}_{n} \in \mathcal{F}_{2}$ or $\mathrm{\phi}_{n} \in \mathcal{F}_{3}$, (P6) is a non-convex problem and we can only obtain a suboptimal solution to (P6).

1) If $\mathrm{\phi}_{n} \in \mathcal{F}_{1}$, constraint (37b) is

$$
\left|\mathrm{\phi}_{n}\right|^{2} \leq 1, \quad \forall \mathit n\in \mathcal{N},
\tag{42}
$$

which can be re-written as follows:

$$
\boldsymbol{\phi}^{\mathrm{H}} \boldsymbol{\varepsilon}_{n} \boldsymbol{\varepsilon}_{n}^{\mathrm{H}} \boldsymbol{\phi} \leq 1, \quad \forall \mathit n\in \mathcal{N},
\tag{43}
$$

where $\boldsymbol{\varepsilon}_{n} \in \mathbb{R}^{N \times 1}$ is a column vector whose elements are all zero except that the $n$th is one. Thus, (P6) can be further transformed into

$$
\begin{aligned}
\text { (P6') }\quad  \min _{\boldsymbol{\phi}} \quad \bar{\mathit{g}}\left(\boldsymbol{\phi}\right) \\
\text { s.t.} \quad \boldsymbol{\phi}^{\mathrm{H}} \boldsymbol{\varepsilon}_{n} \boldsymbol{\varepsilon}_{n}^{\mathrm{H}} \boldsymbol{\phi} \leq 1, \quad \forall \mathit n\in \mathcal{N}.
\end{aligned}
\tag{44}
$$

Note that (P6') is convex and can be solved with KKT conditions. We can write the Lagrangian function corresponding to (P6') as follows:

$$
L(\boldsymbol{\phi}, \boldsymbol{\nu})=\bar{\mathit{g}}\left(\boldsymbol{\phi}\right)+\sum_{n=1}^{N} \nu_{n}\left(\boldsymbol{\phi}^{\mathrm{H}} \boldsymbol{\varepsilon}_{n} \boldsymbol{\varepsilon}_{n}^{\mathrm{H}} \boldsymbol{\phi}-1\right),
\tag{45}
$$

where $\boldsymbol{\nu}= \left[\nu_{1}, \ldots, \nu_{N}\right]$ is the Lagrange multiplier vector with $\nu_n\ge0$ for $\forall \mathit n\in \mathcal{N}$. According to KKT conditions, we have

$$
\begin{cases}
2\mathbf{A}\boldsymbol{\phi}+\mathbf{c}+\mathbf{w}^{\mathrm{H}}+2\sum_{n=1}^N \nu_{n}\boldsymbol{\varepsilon}_{n} \boldsymbol{\varepsilon}_{n}^{\mathrm{H}} \boldsymbol{\phi}=0, \\
	\boldsymbol{\phi}^{\mathrm{H}} \boldsymbol{\varepsilon}_{n} \boldsymbol{\varepsilon}_{n}^{\mathrm{H}} \boldsymbol{\phi}-1 \leq 0, \quad \forall \mathit n\in \mathcal{N}, \\
	\nu_{n}\left(\boldsymbol{\phi}^{\mathrm{H}} \boldsymbol{\varepsilon}_{n} \boldsymbol{\varepsilon}_{n}^{\mathrm{H}} \boldsymbol{\phi}-1\right)=0,\quad  \forall \mathit n\in \mathcal{N}.
\end{cases}
\tag{46}
$$

Solving (46), we can obtain the optimal solution as follows:

$$
\ddot{\boldsymbol{\phi}}^{\mathcal{F}_{1}}=-\frac{1}{2}\left(\sum_{n=1}^{N} \nu_{n} \boldsymbol{\varepsilon}_{n} \boldsymbol{\varepsilon}_{n}^{H}+\mathbf{A}\right)^{-1} \left(\mathbf{c}+\mathbf{w}^{\mathrm{H}}\right),
\tag{47}
$$

where the optimal $\nu_{n}$, denoted by $\ddot{\nu}_{n}$, can be obtained by sub-gradient method or ellipsoid method.

2) If $\mathrm{\phi}_{n} \in \mathcal{F}_{2}$, constraint (37b) is

$$
\left|\mathrm{\phi}_{n}\right|^{2}=1, \quad \forall \mathit n\in \mathcal{N},
\tag{48}
$$

which is equivalent to $\left|\mathrm{\phi}_{n}\right|=1, \forall \mathit n\in \mathcal{N}.$ Then, (P6) can be transformed into the following problem

$$
\text { (P6'') }\quad  \min _{\boldsymbol{\phi}} \quad\bar{\mathit{g}}\left(\boldsymbol{\phi}\right)
\tag{49a}
$$

$$
\text { s.t.} \quad  \left|\phi_{n}\right|=1, \quad \forall \mathit n\in \mathcal{N}
\tag{49b}
$$

Due to the non-convex constraint (49b), (P6'') is a non-convex QCQP. In general, the unit modulus constraint problem is solved by dropping the rank-one constraint using semidefinite relaxation (SDR) method [27]. However, SDR method has high computational complexity and may not converge to a good suboptimal solution. Thus, we propose RCG algorithm to solve (P6'').

According to [33], [34], unit modulus constraint (49b) forms an $N$-dimensional complex circle manifold denoted as follows:

$$
\mathcal{M}_{cc}^{N}=\left\{\boldsymbol{\phi} \in \mathbb{C}^{N}:\left|\phi_{1}\right|=\left|\phi_{2}\right|=\cdots=\left|\phi_{N}\right|=1\right\},
\tag{50}
$$

where complex circle manifold $\mathcal{M}_{cc}^{N}$ is a Riemannian sub-manifold of Riemannian manifold $\mathbb{C}^{N}$. Thus, (P6'') can be formulated as the following problem

$$
\begin{aligned}
\text { (P7) }\quad  \min _{\boldsymbol{\phi} \in \mathcal{M}_{\mathbf{cc}}^{N}} \quad\bar{\mathit{g}}\left(\boldsymbol{\phi}\right),
\end{aligned}
\tag{51}
$$

where (P7) is an unconstrained problem on the surface of $\mathcal{M}_{cc}^{N}$. For any point $\boldsymbol{\phi}_{k}$ on $\mathcal{M}_{cc}^{N}$, the tangent space formed by passing through this point can be represented as

$$
\mathcal{T}  _{\boldsymbol{\phi}_{k}} \mathcal{M}_{cc}^{N}=\left\{\boldsymbol{\mu} \in \mathbb{C}^{N}: \Re\left(\boldsymbol{\mu} \odot \boldsymbol{\phi}_{k}^{*}=\mathbf{0}_{N}\right)\right\},
\tag{52}
$$

where $\boldsymbol{\mu}$ is a tangent vector passing through $\boldsymbol{\phi}_{k}$.

Riemannian gradient [34] is defined as the tangent vector or direction in the Riemannian tangent space, which represents the direction of the fastest change of the objective function. Since $\mathcal{M}_{cc}^{N}$ is a Riemannian sub-manifold, the Riemannian gradient of $\bar{\mathit{g}}\left(\boldsymbol{\phi}_k\right)$ at point $\boldsymbol{\phi}_{k}$, denoted by $\nabla_\mathcal{M} \bar{\mathit{g}}\left(\boldsymbol{\phi}_{k}\right)$, can be expressed as follows:

$$
\begin{aligned}
\nabla_{\mathcal{M}} \bar{\mathit{g}}\left(\boldsymbol{\phi}_{k}\right) =\operatorname{Proj}\left ( \nabla \bar{\mathit{g}}\left(\boldsymbol{\phi}_{k}\right)\right) \\
 =\nabla \bar{\mathit{g}}\left(\boldsymbol{\phi}_{k}\right)-\Re\left\{\nabla \bar{\mathit{g}}\left(\boldsymbol{\phi}_{k}\right) \odot \boldsymbol{\phi}_{k}^{*}\right\} \odot \boldsymbol{\phi}_{k},
\end{aligned}
\tag{53}
$$

where $\operatorname{Proj}\left ( \nabla \bar{\mathit{g}}\left(\boldsymbol{\phi}_{k}\right)\right )$ denotes the orthogonal projection of the Euclidean gradient $\nabla \bar{\mathit{g}}\left(\boldsymbol{\phi}_{k}\right)$ onto $\mathcal{T} _{\boldsymbol{\phi}_{k}} \mathcal{M}_{cc}^{N}$. Through numerical computation, we can obtain the Euclidean gradient $\nabla \bar{\mathit{g}}\left(\boldsymbol{\phi}_{k}\right)$ at point $\boldsymbol{\phi}_{k}$ as follows:

$$
\nabla \bar{\mathit{g}}\left(\boldsymbol{\phi}_{k}\right)=2\mathbf{A}\boldsymbol{\boldsymbol{\phi}}_{k}+\mathbf{c}+\mathbf{w}^{\mathrm{H}}.
\tag{54}
$$

Since the tangent vector obtained from the Riemannian gradient may not lie on the surface of the manifold, we need a retraction operation to map this vector to a new point on the manifold. This map procedure can be expressed as follows:

$$
\begin{aligned}
\boldsymbol{\phi}_{k+1} =\operatorname{Ret}_{\boldsymbol{\phi}_{k}}\left(\delta_{k} \boldsymbol{\gamma}_{k}\right) \\
 \triangleq \mathcal{T}_{\boldsymbol{\phi}_{k}} \mathcal{M}_{c c}^{N} \mapsto \mathcal{M}_{c c}^{N}: \delta_{k} \boldsymbol{\gamma}_{k} \mapsto \operatorname{unit}\left(\frac{\boldsymbol{\phi}_{k}+\delta_{k} \boldsymbol{\gamma}_{k}}{\left|\boldsymbol{\phi}_{k}+\delta_{k} \boldsymbol{\gamma}_{k}\right|}\right),
\end{aligned}
\tag{55}
$$

where $\boldsymbol{\gamma}_{k}$ denotes the search direction passing through $\boldsymbol{\phi}_{k}$, $\delta_{k}$ is the Armijo backtracking line search step size, $\mapsto$ denotes the operation of mapping, and $\operatorname{unit}$ denotes the normalization of vector.

With conjugate gradient descent method, the $(k+1)$th search direction in Euclidean space is

$$
\boldsymbol{\gamma}_{k+1}=-\nabla \bar{\mathit{g}}\left(\boldsymbol{\phi}_{k+1}\right)+\mathfrak{d}_{k} \boldsymbol{\gamma}_{k},
\tag{56}
$$

where $\mathfrak{d}_{k}$ is the Polak-Ribiere parameter of the $k$th iteration [34]. Since $\boldsymbol{\gamma}_{k+1}$ and $\boldsymbol{\gamma}_{k}$ lie on different tangent spaces and cannot be conducted directly with mathematical computation, $\boldsymbol{\gamma}_{k}$ at point $\boldsymbol{\phi}_{k}$ needs to be transported to $\boldsymbol{\gamma}_{k+1}$ at point $\boldsymbol{\phi}_{k+1}$, the transport operation is given by

$$
\begin{aligned}
\mathcal{T}_{\boldsymbol{\phi}_{k}\mapsto\boldsymbol{\phi}_{k+1}}\left(\boldsymbol{\gamma}_{k}\right) =\mathcal{T}_{\boldsymbol{\phi}_{k}} \mathcal{M}_{c c}^{N} \mapsto \mathcal{T}_{\boldsymbol{\phi}_{k+1}}\mathcal{M}_{c c}^{N}\\
 =\boldsymbol{\gamma}_{k}\mapsto\boldsymbol{\gamma}_{k}-\Re\left\{\boldsymbol{\gamma}_{k} \odot \boldsymbol{\phi}_{k}^{*}\right\} \odot \boldsymbol{\phi}_{k}.
\end{aligned}
\tag{57}
$$

With the Riemannian gradient, the $(k+1)$th search direction in the manifold space can be updated by

$$
\boldsymbol{\gamma}_{k+1}=-\nabla _{\mathcal{M}} \bar{\mathit{g}}\left(\boldsymbol{\phi}_{k+1}\right)+\mathfrak{d}_{k} \mathcal{T}_{\boldsymbol{\phi}_{k}\mapsto\boldsymbol{\phi}_{k+1}}\left(\boldsymbol{\gamma}_{k}\right).
\tag{58}
$$


**Algorithm 1: RCG algorithm for solving (P6'')**

1. Initialize with $k=0$, $\boldsymbol{\phi}_{0} \in \mathcal{M}_{c c}^{N}$, and $\boldsymbol{\gamma}_{0}=-\nabla _{\mathcal{M}} \bar{\mathit{g}}\left(\boldsymbol{\phi}_{0}\right)$.
2. **repeat**
3. Choose the step size $\delta_{k}$ by backtracking line search;
4. Update point $\boldsymbol{\phi}_{k+1}$ by (55);
5. Update the Riemannian gradient $\nabla _{\mathcal{M}} \bar{\mathit{g}}\left(\boldsymbol{\phi}_{k+1}\right)$ by (53) and (54);
6. Update the transport operation $\mathcal{T}_{\boldsymbol{\phi}_{k}\mapsto\boldsymbol{\phi}_{k+1}}\left(\boldsymbol{\gamma}_{k}\right)$ by (57);
7. Choose the Polak-Ribiere parameter $\mathfrak{d}_{k}$;
8. Update the new search direction $\boldsymbol{\gamma}_{k+1}$ by (58);
9. $k=k+1$;
10. **until** $\left\|\nabla _{\mathcal{M}} \bar{\mathit{g}}\left(\boldsymbol{\phi}_{k+1}\right)\right\|^{2} \leq \epsilon $.
11. **Return** $\ddot{\boldsymbol{\phi}}^{\mathcal{F}_{2}}=\boldsymbol{\phi}_{k+1}$

The specific procedure of RCG algorithm to solve (P6'') is summarized in Algorithm 1, which continuously updates the gradient search direction based on (58) until the Riemannian gradient $\nabla _{\mathcal{M}} \bar{\mathit{g}}\left(\boldsymbol{\phi}_{k+1}\right)$ converges. The complexity of RCG algorithm is mainly dominated by calculating the Euclidean gradient, which is $O(N^2)$. Thus, the computational complexity of RCG algorithm is $O(I_RN^2)$ where $I_R$ represents the iteration times required by the RCG algorithm. According to [32], the complexity of SDR method is $O(N^{3.5})$. It can be observed that the complexity of RCG algorithm is lower than that of the SDR method.

3) If $\mathrm{\phi}_{n} \in \mathcal{F}_{3}$, the constraint of $\text { (P1) }$ is

$$
\mathrm{\phi}_{n}=e^{j \mathrm{\theta}_{n}},\theta_{n} \in\left\{0, \frac{2 \pi}{\tau}, \cdots, \frac{2 \pi(\tau-1)}{\tau}\right\}.
\tag{59}
$$

We adopt NPP method to deal with the discrete phase and choose to obtain the discrete phase RC from the projection of the continuous phase RC due to the relatively low computational complexity [22]. We denote by $\ddot{\Omega}^{\mathcal{F}_{2}}_{n}$ the angle of the optimal solution to (P6''). Then, for the case where $\phi_{n} \in \mathcal{F}_{3}$, we can obtain the subptimal solution to the discrete phase as follows:

$$
\ddot{\phi}^{\mathcal{F}_{3}}_{n}=e^{j \ddot{\Omega}^{\mathcal{F}_{3}}_{n}},\quad \forall \mathit n\in \mathcal{N},
\tag{60}
$$

where

$$
\ddot{\Omega}^{\mathcal{F}_{3}}_{n}=\arg \min _{\theta_{n} \in\left\{0, \frac{2 \pi}{\tau}, \cdots, \frac{2 \pi(\tau-1)}{\tau}\right\}}\left|\theta_{n}-\ddot{\Omega}^{\mathcal{F}_{2}}_{n}\right| ,\quad \forall \mathit n\in \mathcal{N}.
\tag{61}
$$


### III-D. Overall Algorithm

Based on previous discussions, the AO algorithm to solve (P1) is shown in Algorithm 2. The specific steps of the algorithm are as follows: Firstly, the algorithm starts with initial feasible points $\mathbf p_{1}^{(0)}$ and $\boldsymbol{\phi}^{(0)}$. In the next step, with a fixed solution $\mathbf p_{1}^{(i-1)}$ and $\boldsymbol{\phi}^{(i-1)}$ from the $(i-1)$th iteration, the update of $\mathbf p_{1}^{(i)}$ and $\boldsymbol{\phi}^{(i)}$ is performed alternately using fractional programming techniques in the $i$th iteration. Note that the objective function of (P1) is monotonically non-decreasing, hence Algorithm 2 will eventually converge [11].


**Algorithm 2: Alternating Optimization for Solving (P1)**

1. Initialize with feasible points $\mathbf p_{1}^{(0)}$ and $\boldsymbol{\phi}^{(0)}$.
2. **repeat**
3. Update $\mathbf q^{(i)}$ by (26);
4. Update power allocation vector $\mathbf p_{1}^{(i)}$ by (31);
5. Update $\mathbf l^{(i)}$ by (36);
6. Update RC vector $\boldsymbol{\phi}^{(i)}$ by solving problem (P1);
7. $i=i+1$;
8. **until** the value of the objective function of (P1) reaches convergence.
9. Return the optimal solution $\ddot{\mathbf p}_{1}=\mathbf p_{1}^{(i)}$ and $\ddot{\boldsymbol{\phi}}=\boldsymbol{\phi}^{(i)}$.


## IV. Simulation

In this section, we give simulation results under different conditions to validate the SIC capability and the capacity gain of RIS-assisted FD-OFDM communications over HD-OFDM communications.

We assume that the transmit and receive antenna of each FD device is located at $(-0.02,0,0.04)$ m and $(0.02,0,0.04)$ m, respectively. The number of OFDM subcarriers, the maximum delay spread, and the length of CP is set to $M = 128$, $L_{\rm max}=5$, and $M_{\rm cp}=5$, respectively. We set the distance between two FD devices to 1000 m, the area of each unit cell under the $m$th subcarrrier to $R_m=(\lambda_m / 5)^{2},\forall \mathit m\in \mathcal{M} $, and the reflection efficiency of each RIS to $\eta=\beta=0.8$. Also, the total power of each transmitter is set to $P_1=P_2=P$, the noise power is set to $\sigma_{1}^{2}=-110$ dBm, and $\epsilon=10^{-7}$. The pathloss is given by $L=\zeta s^{-\partial }$, where $s$ is the distance and $\zeta$ is the pathloss at the reference distance of 1 m, which is set to -30 dB with the pathloss exponent of $\partial=2$. If $\mathbf{\Gamma } \in \{\mathit{h}_{m,\rm T1},\mathit{h}_{m,\rm T2}\}, \forall \mathit m\in \mathcal{M} $, we set $K_{\rm r}=6$. If $\mathbf{\Gamma } \in \{\mathbf{g}_{m,12},\mathbf{g}_{m,21},\mathbf{h}_{m,12},\mathbf{h}_{m,21}\}, \forall \mathit m\in \mathcal{M} $, we set $K_{\rm r}=9$. The channels between elements of a RIS and an antenna are assumed to be independent and identically distributed. However, the channels from a RIS to different antennas are assumed to be non-identical. Apart from our schemes developed in Section III, we also introduce benchmark scheme for comparison. The descriptions of our developed and the benchmark scheme are as follows:

1) **Ideal case:** in this scheme, both the RC matrix of the RIS and power allocation vector are optimized to maximize the SIC capability under the case of $\mathrm {\phi}_{n} \in \mathcal{F}_{1}$.

2) **Continuous phases:** we apply RCG algorithm to optimize the RC matrix where $\mathrm {\phi}_{n} \in \mathcal{F}_{2}$.

3) **Discrete phases:** when the phase shift $\mathrm {\phi}_{n}$ belongs to the set $\mathcal{F}_{3}$, we set the number of discrete phases to be $\tau = 2, 4,$ and $8$ for comparison.

4) **Random phases:** we set the random phases scheme as the benchmark scheme. In our assumption, the RC has a random phase that is randomly selected from [0, $2\pi$], while the amplitude is fixed to one [35].


> **Fig. 4** — The convergence behavior of Algorithm 2.


> **Fig. 5** — The SIC capability and capacity gain with different values of $N$.
> Sub-figures: SIC capability.; Capacity gain.

First, we evaluate the convergence behavior of Algorithm 2. The number of RIS elements is set as $N=35$, the transmit power is set as $P=0$ dBm, and the signal bandwidth is set as $B=20$ MHz. If not mentioned otherwise, these parameter settings remain constant throughout the subsequent discussion. We initialize the power allocation vector $\mathbf p_{1}^{(0)}$ as a column vector of zeros and the RC vector $\boldsymbol{\phi}^{(0)}$ as a column vector of ones, except for the random phases scheme where the phase of each unit cell is initialized as a random value selected from [0, $2\pi$]. Fig. 4 shows the SIC capability versus the number of iterations in different conditions. We can observe from Fig. 4 that all curves converge within 5 iterations. To be specific, the ideal case and the continuous phases case converge within 5 iterations, while the other cases converge within 1 iteration. For the ideal phases case, the power allocation vector and RC vector are obtained by solving the KKT conditions, which can be expressed in closed-form expression. Thus, the optimal solution can be obtained in each iteration, resulting in convergence. In addition, the RC vector of the continuous phases case is optimized by the RCG algorithm, which also offers a fast convergence. Thus, the continuous phases curve can converge within 5 iterations. The discrete phases case converges faster than the ideal and continuous phases cases for two reasons. First, the feasible domain of the discrete phases case is small, we only need to choose one of several discrete values as the phase shift. Second, the discrete phases are directly projected from the continuous phases. Thus, we only need to optimize the power allocation without optimizing the RC. Similarly, the random phases are generated randomly, and only the power allocation is optimized, resulting in the same fast convergence speed as the discrete phases. Since both the amplitude and phase of each RIS unit cell can be independently and continuously controlled, the ideal case can achieve the optimal performance, which is consistent with the discussion in Section II.

In Fig. 5, the SIC capability and capacity gain are depicted with different values of $N$. As shown in Fig. 5(a), the SIC capabilities of the ideal case and the continuous phases case increase monotonically as the value of $N$ increases and it can be larger than 85 dB. When $N$ is larger than 32, both the ideal case and the continuous phases case exhibit a consistent SIC capability that remains stable as $N$ increases. The curve of the ideal case can remain stable because the modules of the RC are not fixed to one. This stability of the continuous phases case is achieved because the optimized power allocation vector compensates for the unit modulus constraint and ensures that the SIC capability does not decrease as $N$ increases. Increasing the value of $\tau$ leads to an enhancement in the SIC capability of the discrete phases because the candidate phases approach the ideal phases more closely as $\tau$ increases. However, as compared with the cases of ideal phases and continuous phases, the SIC capability of the discrete phases is weaker due to the phase differences between candidate phases and ideal phases. In the case of discrete phases, the SIC capability fluctuates with the increase of $N$ due to the varying phase differences. At times, these phase differences increase, leading to a decrease in SIC capability. Conversely, there are instances where the phase differences decrease, resulting in an increase in SIC capability. Thus, the fluctuation of SIC capability with $N$ can be attributed to the changing phase differences. This reduction in SIC capability resulting from these phase differences can be compensated by increasing the number of reflecting elements. The SIC achieved with random phases is approximately 20 dB, which is significantly lower than that of the ideal case and the continuous phases case. This result implies the importance of phase shift design in SIC.

The comparison of our proposed RIS-assisted FD-OFDM system with the FD-OFDM system without RISs is shown in Fig. 5(b). The system capacity of FD-OFDM system without RISs are obtained by replacing (21) with

$$
C_{\rm FD}^{\rm N-RISs}=\frac{1}{M+M_{cp}} \sum_{m=0}^{M-1} \mathrm{\log} _{2}\hspace{-1mm}\left(1+\frac{\left|\mathit{h}_{m,\rm T2}\right|^{2} p_{2,m}}{\kappa\left|\mathit{h}_{m,1}\right|^{2} p_{1,m}+\sigma_{1}^{2}}\right),
\tag{62}
$$

where $0 \le \kappa \le 1$ is the SIC coefficient [36], [37], [38]. When $\kappa = 0$, the SI is perfectly canceled. On the other hand, when $\kappa = 1$, SIC techniques are invalid. To better clarify the capacity gain of the proposed RIS-assisted FD-OFDM communication system over FD-OFDM system without RISs, we set $\kappa = 1/(87 \rm ~dB)$ where 87 dB is the SIC capability of RIS-assisted FD-OFDM system. As illustrated in Fig. 5(b), the capacity gain is initially close to zero due to the strong SI. However, the capacity gain gradually increases as $N$ increases, and then ultimately reaches a steady state. It is worth noting that although RISs are deployed to cancel the SI, the RIS-assisted link indirectly strengthens the desired signal. Thus, the capacity gain of the proposed RIS-assisted FD-OFDM communication system over HD-OFDM system without RISs can be more than 2.25 times. With the same SIC capability, we can observe that the capacity gain of RIS-assisted FD-OFDM communication system over FD-OFDM system without RISs is 1.13, which confirms that RIS can significantly improve the capacity as compared with FD-OFDM communication system without RISs. This is because the RIS-assisted link not only cancels the SI but also strengthens the desired signal. The results in Fig. 5 demonstrate the feasibility of deploying RIS for SIC and provide a novel approach for SIC in the propagation domain for FD communications.


> **Fig. 6** — The SIC capability with different values of $P$.


> **Fig. 7** — The SIC capability with different values of $B$.

Figure Fig. 6 plots the SIC capability corresponding to the total transmit power $P$. Fig. 6 illustrates that as $P$ increases, the SIC capabilities of the ideal case and the continuous phases case increase accordingly. However, the SIC capability of the continuous phases case is weaker than that of the ideal case due to the unit modulus constraint imposed on each RIS units, which limits its performance. In cases of discrete phases and random phases, the SIC capabilities are not affected by transmit power. Hence, increasing $P$ fails to improve the SIC capability. This outcome is attributed to the inadequate cancellation of SI. The residual SI remains very strong, which diminishes the significance of transmit power in increasing the SIC capability.

In Fig. 7, the SIC capability of the proposed scheme with different values of signal bandwidth $B$ is presented. Fig. 7 shows that the SIC capabilities of all curves, except for the ideal case and the random phases case, decreases as $B$ increases. The reason for the curve of the ideal case remains unchanged is that the SI is effectively canceled, so it is not affected by bandwidth. The reason why the case of random phases is not affected by bandwidth, as same as Fig. 6, is the strong residual SI. The performance of the continuous phases case is similar to the ideal case when $B=5$ MHz, and then the SIC capability drops to $80$ dB when $B=55$ MHz due to the unit-modulus constraint. In practical design of RIS phase shift, passive beamforming with phase gradient metasurfaces can be used to cancel SI. The phase difference between different frequency points in the feasible signal bandwidth range is relatively constant, which implies that signal bandwidth has no impact on the SIC capability. The aforementioned development is encouraging, as it suggests that the implementation of RISs to cancel SI in FD broadband communications is feasible.

We can utilize phase discretization to simulate the phase errors of continuous phases. As the number of discrete phases increases, the phase errors decrease. When the number of phases approaches infinity, the phase errors become zero. The phase errors are defined by

$$
\Delta \Omega_{n}=\left|\ddot{\Omega}^{\mathcal{F}_{3}}_{n}-\ddot{\Omega}^{\mathcal{F}_{2}}_{n}\right| \approx \frac{360^{\circ}}{\tau }  ,\quad \forall \mathit n\in \mathcal{N},
\tag{63}
$$

where $\ddot{\Omega}^{\mathcal{F}_{2}}_{n}$ denotes the ideal phase of the continuous phases case and $\ddot{\Omega}^{\mathcal{F}_{3}}_{n}$ is the actual phase of the $n$th unit cell selected from the $\tau$ available phases.

Figure Fig. 8 presents the SIC capability corresponding to different numbers of discrete phases $\tau$. We set $\tau$ to increase by $2^\omega $, where $\omega$ is the resolution bits for the discrete phases.


> **Fig. 8** — The SIC capability with with different values of $\tau$.

As shown in Fig. 8, the SIC capability gradually increases as $\tau$ increases. When $\tau\ge512$, the SIC capability of the discrete phases is close to that of the continuous phases, with phase errors of about $0.7^{\circ}$. When $\tau\ge128$, i.e., the phase error is $2.8^{\circ}$, which is larger than the actual engineering design error [39], [40]. However, the SIC capability only decreases by 5 dB, and there is still 80 dB of SIC capability, which is enough to ensure the performance of the RIS. Thus, the phase accuracy of the proposed RIS-assisted FD-OFDM communication system is sufficient.

The size of RIS is the primary limiting factor for deploying it inside a device. For the considered 5.8 GHz band, RIS can be deployed inside a device since its size can be relatively small. The RIS unit side length can typically be selected between $\lambda/10$ and $\lambda/2$ [4], [24]. We can set the RIS unit length to $\lambda/5$. For the case where the operating frequency is $f=5.8$ GHz, the wavelength is $\lambda=c/f=0.0517$ m, and the area of RIS unit cell is $\left ( \lambda/5 \right )^2\approx \left ( 0.01 \right )^2 \rm m^2$. As shown in Fig. 5(a) of this paper, a total of 36 RIS units are required to achieve maximum SIC capability. Therefore, the size of RIS is approximately $60 \times 60~\rm mm^2$, which can be deployed inside some terminal products, such as HUAWEI CPE series.


## V. Conclusions

In this paper, we proposed and analyzed a novel SIC scheme based on RIS for FD-OFDM communications. First, we analyzed the near-field behavior of the RIS and found the relationships between near-field channel and performance optimization. We then formulated an optimization problem to maximize the SIC capability by controlling the RC of the RIS and allocating the transmit power of the device. Finally, we utilized the AO algorithm to solve the problem in ideal case, continuous phases, and discrete phases. Simulation results showed that the proposed RIS-based SIC scheme can cancel the SI by more than 85 dB in the ideal case and the continuous phases case. Furthermore, we evaluated the impact of phase errors caused by small-sized RIS in SIC capability. The unsignificant difference in SIC capability between two cases indicates that the low-complexity RIS with fixed amplitude of 1 is a viable option. Also, the capacity gain of the proposed RIS-assisted FD-OFDM system over HD-OFDM system without RISs can be more than 2.25 times due to the enhancement for the effective path of the desired signal. These encouraging results suggest that RIS can provide an attractive way to achieve FD communications.


## References

[1] W. Cheng, W. Zhang, L. Liang, and H. Zhang, "Full-duplex for multi-channel cognitive radio ad hoc networks," *IEEE Network*, vol. 33, no. 2, pp. 118–124, 2019.

[2] S. A. Jiménez, J. S. Garcia, and F. R. C. Soria, "Self interference cancellation on a full duplex DFTs-OFDM system using GNU radio and USRP," *IEEE Latin America Transactions*, vol. 19, no. 10, pp. 1781–1789, 2021.

[3] S. M. Kim, Y. G. Lim, L. Dai, and C. B. Chae, "Performance analysis of self-interference cancellation in full-duplex massive MIMO systems: subtraction versus spatial suppression," *arXiv preprint arXiv:2205.14475*, 2022.

[4] W. Tang, M. Z. Chen, X. Chen, J. Y. Dai, Y. Han, M. D. Renzo, Y. Zeng, S. Jin, Q. Cheng, and T. J. Cui, "Wireless communications with reconfigurable intelligent surface: path loss modeling and experimental measurement," *IEEE Transactions on Wireless Communications*, vol. 20, no. 1, pp. 421–439, 2021.

[5] H. Shen, T. Ding, W. Xu, and C. Zhao, "Beamformig design with fast convergence for IRS-aided full-duplex communication," *IEEE Communications Letters*, vol. 24, no. 12, pp. 2849–2853, 2020.

[6] N. V. Deshpande, S. Dey, D. N. Amudala, and R. Budhiraja, "Spatially-correlated IRS-aided multiuser FD mMIMO systems: analysis and optimization," *IEEE Transactions on Communications*, vol. 70, no. 6, pp. 3879–3896, 2022.

[7] P. K. Sharma and P. Garg, "Intelligent reflecting surfaces to achieve the full-duplex wireless communication," *IEEE Communications Letters*, vol. 25, no. 2, pp. 622–626, 2020.

[8] S. Dhok and P. K. Sharma, "Infinite and Finite Block-length FD Transmissions with Spatially-correlated RIS Channels," *IEEE Transactions on Wireless Communications*, 2022.

[9] S. Zhang and R. Zhang, "Capacity characterization for intelligent reflecting surface aided MIMO communication," *IEEE Journal on Selected Areas in Communications*, vol. 38, no. 8, pp. 1823–1838, 2020.

[10] Z. Wei, Y. Cai, Z. Sun, D. W. K. Ng, J. Yuan, M. Zhou, and L. Sun, "Sum-rate maximization for IRS-assisted UAV OFDMA communication systems," *IEEE Transactions on Wireless Communications*, vol. 20, no. 4, pp. 2530–2550, 2021.

[11] W. Jiang, B. Chen, J. Zhao, Z. Xiong, and Z. Ding, "Joint active and passive beamforming design for the IRS-assisted MIMOME-OFDM secure communications," *IEEE Transactions on Vehicular Technology*, vol. 70, no. 10, pp. 10369–10381, 2021.

[12] S. Aboagye, A. R. Ndjiongue, T. M. Ngatched, O. A. Dobre, and H. V. Poor, "RIS-assisted visible light communication systems: A tutorial," *IEEE Communications Surveys & Tutorials*, 2022.

[13] S. Aboagye, A. R. Ndjiongue, T. M. Ngatched, and O. A. Dobre, "Design and Optimization of Liquid Crystal RIS-Based Visible Light Communication Receivers," *IEEE Photonics Journal*, vol. 14, no. 6, pp. 1–7, 2022.

[14] X. Yang, E. Wen, and D. F. Sievenpiper, "Power-dependent metasurface with self-induced bandgap," *IEEE Antennas and Wireless Propagation Letters*, vol. 21, no. 6, pp. 1115–1119, 2022.

[15] A. K. Baghel, S. S. Kulkarni, and S. K. Nayak, "Linear-to-cross-polarization transmission converter using ultrathin and smaller periodicity metasurface," *IEEE Antennas and Wireless Propagation Letters*, vol. 18, no. 7, pp. 1433–1437, 2019.

[16] M. M. Amri, "Recent Trends in the Reconfigurable Intelligent Surfaces (RIS): Active RIS to Brain-controlled RIS," in *2022 IEEE International Conference on Communication, Networks and Satellite (COMNETSAT)*, 2022, pp. 299–304.

[17] L. Zhang, X. Q. Chen, S. Liu, Q. Zhang, J. Zhao, J. Y. Dai, G. D. Bai, X. Wan, Q. Cheng, G. Castaldi et al., "Space-time-coding digital metasurfaces," *Nature communications*, vol. 9, no. 1, p. 4334, 2018.

[18] R. B. Green, K. Ding, V. Avrutin, U. Ozgur, and E. Topsakal, "Optically transparent antenna arrays for the next generation of mobile networAks," *IEEE Open Journal of Antennas and Propagation*, vol. 3, pp. 538–548, 2022.

[19] W. L. Stutzman and G. A. Thiele, *Antenna theory and design*. John Wiley & Sons, 2012.

[20] A. D. J. Torres, L. Sanguinetti, and E. Björnson, "Near-and far-field communications with large intelligent surfaces," in *2020 54th Asilomar Conference on Signals, Systems, and Computers*, 2020, pp. 564–568.

[21] L. You, J. Xiong, D. W. K. Ng, C. Yuen, W. Wang, and X. Gao, "Energy efficiency and spectral efficiency tradeoff in RIS-aided multiuser MIMO uplink transmission," *IEEE Transactions on Signal Processing*, vol. 69, pp. 1407–1421, 2021.

[22] H. Guo, Y. C. Liang, J. Chen, and E. G. Larsson, "Weighted sum-rate optimization for intelligent reflecting surface enhanced wireless networks," *arXiv preprint arXiv:1905.07920*, 2019.

[23] M. Hua and Q. Wu, "Joint dynamic passive beamforming and resource allocation for IRS-aided full-duplex WPCN," *IEEE Transactions on Wireless Communications*, 2022.

[24] E. Björnson and L. Sanguinetti, "Power scaling laws and near-field behaviors of massive MIMO and intelligent reflecting surfaces," *IEEE Open Journal of the Communications Society*, vol. 1, pp. 1306–1324, 2020.

[25] D. Dardari, "Communicating with large intelligent surfaces: fundamental limits and models," *IEEE Journal on Selected Areas in Communications*, vol. 38, no. 11, pp. 2526–2537, 2020.

[26] W. Tang, J. Y. Dai, M. Z. Chen, K. K. Wong, X. Li, X. Zhao, S. Jin, Q. Cheng, and T. J. Cui, "MIMO transmission through reconfigurable intelligent surface: System design, analysis, and implementation," *IEEE Journal on Selected Areas in Communications*, vol. 38, no. 11, pp. 2683–2699, 2020.

[27] Q. Wu and R. Zhang, "Intelligent reflecting surface enhanced wireless network: joint active and passive beamforming design," in *2018 IEEE Global Communications Conference (GLOBECOM)*, 2018, pp. 1–6.

[28] J. An, C. Xu, L. Gan, and L. Hanzo, "Low-complexity channel estimation and passive beamforming for RIS-assisted MIMO systems relying on discrete phase shifts," *IEEE Transactions on Communications*, vol. 70, no. 2, pp. 1245–1260, 2022.

[29] Z. Sun and Y. Jing, "On the performance of multi-antenna IRS-assisted NOMA networks with continuous and discrete IRS phase shifting," *IEEE Transactions on Wireless Communications*, vol. 21, no. 5, pp. 3012–3023, 2022.

[30] W. Cheng, J. Wang, R. Zhang, and H. Zhang, "Achieving maximum spectrum efficiency for full-duplex MIMO: the fractal array-element based self-interference mitigation approach," *IEEE Access*, vol. 7, pp. 74056–74069, 2019.

[31] K. Shen and W. Yu, "Fractional programming for communication systems—part i: Power control and beamforming," *IEEE Transactions on Signal Processing*, vol. 66, no. 10, pp. 2616–2630, 2018.

[32] S. Boyd, S. P. Boyd, and L. Vandenberghe, *Convex optimization*. Cambridge university press, 2004.

[33] R. Li, B. Guo, M. Tao, Y.-F. Liu, and W. Yu, "Joint design of hybrid beamforming and reflection coefficients in RIS-aided mmWave MIMO systems," *IEEE Transactions on Communications*, vol. 70, no. 4, pp. 2404–2416, 2022.

[34] P. Absil, R. Mahony, and R. Sepulchre, *Optimization algorithms on matrix manifolds*. Princeton University Press, 2008.

[35] Z. Zhang and L. Dai, "A joint precoding framework for wideband reconfigurable intelligent surface-aided cell-free network," *IEEE Transactions on Signal Processing*, vol. 69, pp. 4085–4101, 2021.

[36] W. Cheng, X. Zhang, and H. Zhang, "Optimal dynamic power control for full-duplex bidirectional-channel based wireless networks," in *2013 Proceedings IEEE INFOCOM*, 2013, pp. 3120–3128.

[37] G. Yang and M. Xiao, "Performance analysis of millimeter-wave relaying: Impacts of beamwidth and self-interference," *IEEE Transactions on Communications*, vol. 66, no. 2, pp. 589–600, 2017.

[38] I. A. Mahady, E. Bedeer, S. Ikki, and H. Yanikomeroglu, "Energy efficiency maximization of full-duplex NOMA systems with improper Gaussian signaling under imperfect self-interference cancellation," *IEEE Communications Letters*, vol. 26, no. 7, pp. 1613–1617, 2022.

[39] H. Ali, M. U. Afzal, K. P. Esselle, and R. M. Hashmi, "Integration of geometrically different elements to design thin near-field metasurfaces," *IEEE Access*, vol. 8, pp. 225336–225346, 2020.

[40] J. Wang and Y. Ramhat-Samii, "Phase method: A more precise beam steering model for phase-delay metasurface based risley antenna," in *2019 URSI International Symposium on Electromagnetic Theory (EMTS)*. IEEE, 2019, pp. 1–4.
