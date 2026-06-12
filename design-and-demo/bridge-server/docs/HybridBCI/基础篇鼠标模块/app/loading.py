from PyQt5.QtWidgets import QWidget, QLabel, QVBoxLayout
from PyQt5.QtCore import Qt, QTimer
from PyQt5.QtGui import QPainter, QColor, QPen


# 旋转加载动画控件
class SpinnerLabel(QLabel):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setFixedSize(80, 80)

        # 开启控件透明
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.setAttribute(Qt.WA_NoSystemBackground)

        self._angle = 0
        self._is_loading = True
        self._color = QColor(46, 166, 255)

        self._timer = QTimer(self)
        self._timer.timeout.connect(self.update_angle)

    # 开始旋转动画
    def start(self):
        self._is_loading = True
        self._timer.start(10)
        self.update()

    # 停止动画
    def stop(self):
        self._timer.stop()
        self.update()

    # 切换为完成状态
    def finish(self):
        self._is_loading = False
        self._timer.stop()
        self.update()

    def update_angle(self):
        self._angle = (self._angle + 5) % 360
        self.update()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.fillRect(self.rect(), Qt.transparent)

        size = min(self.width(), self.height())
        rect_size = size - 16
        cx = self.width() / 2
        cy = self.height() / 2
        arc_x = int(cx - rect_size / 2)
        arc_y = int(cy - rect_size / 2)

        if self._is_loading:
            pen = QPen(self._color, 8, Qt.SolidLine)
            pen.setCapStyle(Qt.RoundCap)
            painter.setPen(pen)
            start_angle = (-90 + self._angle) * 16
            span_angle = 270 * 16
            painter.drawArc(arc_x, arc_y, rect_size, rect_size, start_angle, span_angle)
        else:
            # 绘制绿色完成圆环
            ring_color = QColor(34, 197, 94)
            ring_pen = QPen(ring_color, 8)
            ring_pen.setCapStyle(Qt.RoundCap)
            painter.setPen(ring_pen)
            painter.drawArc(arc_x, arc_y, rect_size, rect_size, 0, 360 * 16)

            # 绘制绿色对勾
            check_pen = QPen(ring_color, 6)
            check_pen.setCapStyle(Qt.RoundCap)
            painter.setPen(check_pen)
            r = rect_size / 2
            painter.drawLine(int(cx - r * 0.35), int(cy + r * 0.05), int(cx - r * 0.10), int(cy + r * 0.30))
            painter.drawLine(int(cx - r * 0.10), int(cy + r * 0.30), int(cx + r * 0.35), int(cy - r * 0.25))


# 透明加载弹窗
class LoadingWidget(QWidget):
    def __init__(self, parent):
        super().__init__(parent)
        self.setWindowFlags(Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint)
        self.setFixedSize(200, 200)
        self.setAttribute(Qt.WA_TranslucentBackground)

        # 布局
        layout = QVBoxLayout(self)
        layout.setAlignment(Qt.AlignCenter)
        layout.setContentsMargins(20, 20, 20, 20)
        layout.setSpacing(10)

        self.spinner = SpinnerLabel()
        self.text_label = QLabel("报告上传中")
        self.text_label.setStyleSheet("color: #2EA6FF; font-size:16px; background:transparent;")
        self.text_label.setAlignment(Qt.AlignCenter)

        layout.addWidget(self.spinner, alignment=Qt.AlignHCenter)
        layout.addWidget(self.text_label)

    # 显示加载状态
    def show(self):
        self.text_label.setText("报告上传中")
        self.text_label.setStyleSheet("color: #2EA6FF; font-size:16px; background:transparent;")
        self.spinner.start()
        self.center()
        super().show()

    # 隐藏加载窗
    def hide(self):
        self.spinner.stop()
        super().hide()

    # 显示完成状态，2秒后自动关闭
    def finish_loading(self, finish_text="上传完成\n请到科创平台查看"):
        self.spinner.finish()
        self.text_label.setText(finish_text)
        self.text_label.setStyleSheet("color: #22C55E; font-size:16px; background:transparent;")
        QTimer.singleShot(2000, self.hide)

    # 窗口居中
    def center(self):
        if self.parent():
            pr = self.parent().geometry()
            x = (pr.width() - self.width()) // 2
            y = (pr.height() - self.height()) // 2
            self.move(x, y)