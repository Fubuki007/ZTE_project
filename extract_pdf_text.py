import PyPDF2
import sys
import os

pdf_path = r"d:\AA 学习项目\AAA 智能反射面辅助通信感知\V8.3.1.1 二次重构 修复距离采用真实值\An_ESPRIT-Based_Moving_Target_Sensing_Method_for_MIMO-OFDM_ISAC_Systems(1).pdf"
output_path = "esprit_extracted.txt"

try:
    with open(pdf_path, 'rb') as file:
        reader = PyPDF2.PdfReader(file)
        text = ""
        for page in reader.pages:
            text += page.extract_text() + "\n"
        
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(text)
    print(f"Text extracted to {output_path}")
except Exception as e:
    print(f"Error: {e}")
