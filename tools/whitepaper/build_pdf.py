"""Build the review PDF from WHITEPAPER.md using ReportLab."""
from pathlib import Path
import re, html
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, KeepTogether, Flowable
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib import colors
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.enums import TA_CENTER

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/pdf/revoked-whitepaper.pdf'
OUT.parent.mkdir(parents=True,exist_ok=True)
for name,file in [('Body','NotoSerif-Regular.ttf'),('BodyBold','NotoSerif-Bold.ttf'),('Sans','NotoSans-Regular.ttf'),('SansBold','NotoSans-Bold.ttf')]:
 pdfmetrics.registerFont(TTFont(name,'/usr/share/fonts/noto/'+file))
pdfmetrics.registerFontFamily('Body',normal='Body',bold='BodyBold',italic='Body',boldItalic='BodyBold')
pdfmetrics.registerFontFamily('Sans',normal='Sans',bold='SansBold',italic='Sans',boldItalic='SansBold')
INK=colors.HexColor('#182b36');ACCENT=colors.HexColor('#98603d');PALE=colors.HexColor('#eef3f5')
styles=getSampleStyleSheet()
styles.add(ParagraphStyle(name='Text',fontName='Body',fontSize=9.7,leading=14.4,textColor=INK,spaceAfter=8,allowWidows=0,allowOrphans=0))
styles.add(ParagraphStyle(name='Major',fontName='SansBold',fontSize=17,leading=22,textColor=INK,spaceBefore=17,spaceAfter=10,keepWithNext=True))
styles.add(ParagraphStyle(name='Minor',fontName='SansBold',fontSize=11.5,leading=16,textColor=INK,spaceBefore=12,spaceAfter=7,keepWithNext=True))
styles.add(ParagraphStyle(name='Cell',fontName='Sans',fontSize=8,leading=11,textColor=INK))
styles.add(ParagraphStyle(name='SmallText',fontName='Sans',fontSize=8,leading=11,textColor=INK,spaceAfter=7))
styles.add(ParagraphStyle(name='TitlePaper',fontName='SansBold',fontSize=31,leading=38,textColor=INK,spaceAfter=22))

def fmt(s):
 s=s.replace('—',' - ').replace('–','-').replace('‑','-')
 s=html.escape(s)
 def link(m):
  label,url=m.group(1),html.unescape(m.group(2))
  if '://' not in url:
   # Local evidence remains a printed path, usable with the source checkout.
   return label+' <font size="7" color="#60727d">('+html.escape(url)+')</font>'
  return '<link href="'+html.escape(url,quote=True)+'" color="#326580">'+label+'</link>'
 s=re.sub(r'\[([^\]]+)\]\(([^)]+)\)',link,s)
 s=re.sub(r'\*\*(.+?)\*\*',r'<b>\1</b>',s)
 s=re.sub(r'`([^`]+)`',r'<font name="Sans" size="9">\1</font>',s)
 return s

class Diagram(Flowable):
 def __init__(self,kind):
  Flowable.__init__(self);self.kind=kind;self.width=475;self.height=[155,300,190][kind]
 def draw(self):
  c=self.canv
  def box(x,y,w,h,label):
   c.setFillColor(PALE);c.setStrokeColor(colors.HexColor('#a7bac3'));c.roundRect(x,y,w,h,5,fill=1)
   p=Paragraph(label,ParagraphStyle('d',parent=styles['Cell'],alignment=TA_CENTER));pw,ph=p.wrap(w-12,h);p.drawOn(c,x+6,y+(h-ph)/2)
  def arrow(x,y,xx,yy):
   import math
   c.setStrokeColor(ACCENT);c.setLineWidth(1);c.line(x,y,xx,yy)
   a=math.atan2(yy-y,xx-x)
   for d in [-.45,.45]:c.line(xx,yy,xx-6*math.cos(a+d),yy-6*math.sin(a+d))
  if self.kind==0:
   box(0,80,100,40,'Recipient');box(135,80,135,40,'Resolve grant<br/>State and access gates');box(310,100,160,40,'Permitted: current values');box(310,30,160,40,'Refused: no values')
   arrow(100,100,135,100);arrow(270,105,310,120);arrow(270,90,310,50)
  elif self.kind==1:
   xs=[35,230,415]
   for x,label in zip(xs,['Ada','Origin server','Shop']):
    box(x-30,265,90 if x==35 else 85,28,label);c.setStrokeColor(colors.HexColor('#a7bac3'));c.line(x+10,20,x+10,260)
   events=[(0,1,'Approve address grant'),(2,1,'Resolve: address A + freshness'),(0,1,'Update address to B'),(2,1,'Resolve again before shipment'),(1,2,'Return B; shop stores shipment snapshot'),(0,1,'Revoke grant'),(2,1,'Fresh read observes revoked state'),(1,2,'Revoked; no values')]
   for i,(a,b,label) in enumerate(events):
    y=245-i*28;arrow(xs[a]+10,y,xs[b]+10,y)
    p=Paragraph(label,ParagraphStyle('e',parent=styles['Cell'],fontSize=7.3,leading=9,alignment=TA_CENTER));w=abs(xs[b]-xs[a]);p.wrap(w,20);p.drawOn(c,min(xs[a],xs[b])+10,y+4)
  else:
   box(160,140,155,35,'Owner app and device keys');box(160,65,155,45,'Revoked server<br/>Vault and grant state');box(0,65,125,45,'Recipient or service');box(345,65,125,45,'Peer server');box(160,0,155,30,'DNS root-key pin')
   arrow(237,140,237,110);arrow(125,87,160,87);arrow(345,87,315,87);arrow(237,30,237,65)

def footer(c,doc):
 c.setStrokeColor(colors.HexColor('#cdd8dd'));c.line(60,43,535,43)
 c.setFont('Sans',7.5);c.setFillColor(colors.HexColor('#60727d'));c.drawString(60,30,'REVOKED  /  REVIEW EDITION 0.6  /  12 NOVEMBER 2026');c.drawRightString(535,30,str(doc.page))
 if doc.page>1:
  c.setFont('Sans',7.5);c.drawString(60,807,'LIVING GRANTS FOR OWNER-CONTROLLED DATA EXCHANGE')

lines=(ROOT/'WHITEPAPER.md').read_text().splitlines();story=[]
story += [Spacer(1,75),Paragraph('REVOKED',styles['Minor']),Paragraph('Living Grants for<br/>Owner-Controlled<br/>Data Exchange',styles['TitlePaper']),Paragraph('Technical white paper<br/>Review edition 0.6 · 12 November 2026',styles['Minor']),Spacer(1,25),Paragraph('An experimental architecture for maintaining data at its source, granting continuing access, and withdrawing future retrieval.',styles['Text']),Spacer(1,25),Paragraph('Prepared for project-author review. Includes implementation evidence and limited local experiments. No production-capacity, comprehensive security, or independent cryptographic validation claim is made.',styles['SmallText']),Spacer(1,40),Paragraph('Reading guide',styles['Minor']),Paragraph('Concept and worked example · Sections 1-2<br/>Architecture and trust · Sections 3-7<br/>Challenges and measured observations · Sections 8-9<br/>Related work, conclusion and evidence · Sections 10-11 and references',styles['Text']),PageBreak()]
i=4;diagram=0
while i<len(lines):
 line=lines[i].strip()
 if not line:i+=1;continue
 if line.startswith('```mermaid'):
  while i<len(lines) and lines[i].strip()!='```':i+=1
  captions=['Figure 1. Grant resolution and its decision boundary.','Figure 2. An address grant from approval through withdrawal.','Figure 3. Components and principal trust relationships.']
  story.append(KeepTogether([Diagram(diagram),Paragraph(captions[diagram],styles['SmallText']),Spacer(1,8)]));diagram+=1;i+=1;continue
 if line.startswith('|'):
  rows=[]
  while i<len(lines) and lines[i].strip().startswith('|'):
   vals=[v.strip() for v in lines[i].strip().strip('|').split('|')]
   if not all(re.fullmatch('[-: ]+',v) for v in vals):rows.append(vals)
   i+=1
  count=len(rows[0]);widths={2:[108,367],3:[100,178,197]}[count]
  cells=[[Paragraph(fmt(v),styles['Cell']) for v in row] for row in rows]
  tbl=Table(cells,colWidths=widths,repeatRows=1,hAlign='LEFT')
  tbl.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),colors.HexColor('#dfe9ee')),('ROWBACKGROUNDS',(0,1),(-1,-1),[colors.white,colors.HexColor('#f5f7f8')]),('VALIGN',(0,0),(-1,-1),'TOP'),('LEFTPADDING',(0,0),(-1,-1),8),('RIGHTPADDING',(0,0),(-1,-1),8),('TOPPADDING',(0,0),(-1,-1),7),('BOTTOMPADDING',(0,0),(-1,-1),7),('LINEBELOW',(0,0),(-1,0),.6,colors.HexColor('#a7bac3'))]))
  story +=[KeepTogether([tbl,Spacer(1,10)]) if len(rows)<=5 else tbl,Spacer(1,10)];continue
 if line.startswith('## '):story.append(Paragraph(fmt(line[3:]),styles['Major']))
 elif line.startswith('### '):story.append(Paragraph(fmt(line[4:]),styles['Minor']))
 else:
  while i+1<len(lines) and lines[i+1].strip() and not lines[i+1].startswith(('#','|','```')) and not re.match(r'^\d+\. ',lines[i+1]):
   i+=1;line+=' '+lines[i].strip()
  story.append(Paragraph(fmt(line),styles['SmallText'] if re.match(r'^\d+\. ',line) else styles['Text']))
 i+=1
SimpleDocTemplate(str(OUT),pagesize=(595.28,841.89),leftMargin=60,rightMargin=60,topMargin=55,bottomMargin=58,title='Revoked: Living Grants for Owner-Controlled Data Exchange',author='Revoked project',subject='Review edition 0.6 - experimental architecture and limited local evaluation').build(story,onFirstPage=footer,onLaterPages=footer)
print(OUT)
