# 1. 우분투 최신 안정버전을 기반으로 시작
FROM ubuntu:22.04

# 2. 타임존 에러 방지 및 필수 빌드 도구(ARM 컴파일러, SSH) 설치
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    gcc-arm-none-eabi \
    cmake \
    make \
    git \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

# 3. CLion 연동을 위한 SSH 및 root 비밀번호 설정
RUN mkdir /var/run/sshd && \
    echo 'root:root' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

# 4. 컨테이너 내부의 기본 작업 디렉토리 설정
WORKDIR /workspace

# 5. 컨테이너가 켜질 때 22번 포트를 열고 SSH 서비스를 자동으로 백그라운드 구동
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]