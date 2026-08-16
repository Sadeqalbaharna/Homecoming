from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4
from reportlab.lib.colors import HexColor, white
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.lib.units import mm

OUT = Path(__file__).resolve().parents[1]
PDF = OUT / "table_ready_session_zero_group_compatibility_kit_v1.pdf"

W, H = A4
NAVY = HexColor("#17324D")
INK = HexColor("#20313D")
TEAL = HexColor("#168C8C")
MINT = HexColor("#DFF4F1")
CORAL = HexColor("#EF765E")
GOLD = HexColor("#F2B84B")
CREAM = HexColor("#FFF9EF")
PALE = HexColor("#F2F6F7")
MID = HexColor("#607985")
LINE = HexColor("#B9C9CD")

c = canvas.Canvas(str(PDF), pagesize=A4, pageCompression=1)
c.setTitle("Table Ready - Session Zero & Group Compatibility Kit")
c.setAuthor("Find My Table")
c.setSubject("System-neutral pre-campaign compatibility worksheets")

def wrap(text, font, size, width):
    words = text.split()
    lines, current = [], ""
    for word in words:
        trial = word if not current else current + " " + word
        if stringWidth(trial, font, size) <= width:
            current = trial
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines

def text(x, y, value, size=9.2, color=INK, font="Helvetica", width=None, leading=None):
    c.setFillColor(color)
    c.setFont(font, size)
    lines = wrap(value, font, size, width) if width else value.split("\n")
    leading = leading or size * 1.35
    for line in lines:
        c.drawString(x, y, line)
        y -= leading
    return y

def footer(page):
    c.setStrokeColor(LINE)
    c.line(18*mm, 15*mm, W-18*mm, 15*mm)
    c.setFont("Helvetica", 7.5)
    c.setFillColor(MID)
    c.drawString(18*mm, 10.5*mm, "TABLE READY  |  v1.0  |  personal-use worksheet")
    c.drawRightString(W-18*mm, 10.5*mm, str(page))

def page_header(kicker, title, intro, page):
    c.setFillColor(CREAM)
    c.rect(0, 0, W, H, fill=1, stroke=0)
    c.setFillColor(TEAL)
    c.roundRect(18*mm, H-29*mm, 34*mm, 8*mm, 4*mm, fill=1, stroke=0)
    c.setFillColor(white)
    c.setFont("Helvetica-Bold", 7.5)
    c.drawCentredString(35*mm, H-26.2*mm, kicker.upper())
    c.setFillColor(NAVY)
    c.setFont("Helvetica-Bold", 22)
    c.drawString(18*mm, H-42*mm, title)
    y = text(18*mm, H-50*mm, intro, 9.2, MID, width=W-36*mm, leading=12)
    footer(page)
    return y - 4*mm

def label_line(y, label, lines=1, hint=None):
    c.setFillColor(NAVY)
    c.setFont("Helvetica-Bold", 8.5)
    c.drawString(18*mm, y, label)
    if hint:
        c.setFont("Helvetica", 7.5)
        c.setFillColor(MID)
        c.drawRightString(W-18*mm, y, hint)
    y -= 4*mm
    c.setStrokeColor(LINE)
    for _ in range(lines):
        c.line(18*mm, y, W-18*mm, y)
        y -= 7*mm
    return y

def check_row(y, options, columns=3, size=8.2):
    usable = W-36*mm
    colw = usable/columns
    for i, option in enumerate(options):
        row, col = divmod(i, columns)
        x = 18*mm + col*colw
        yy = y - row*7*mm
        c.setStrokeColor(TEAL)
        c.rect(x, yy-2.5*mm, 3.5*mm, 3.5*mm, fill=0, stroke=1)
        text(x+5*mm, yy-1.8*mm, option, size, INK, width=colw-6*mm, leading=9)
    rows = (len(options)+columns-1)//columns
    return y - rows*7*mm - 2*mm

def note_box(y, title, height=22*mm, fill=PALE):
    c.setFillColor(fill)
    c.setStrokeColor(LINE)
    c.roundRect(18*mm, y-height, W-36*mm, height, 3*mm, fill=1, stroke=1)
    c.setFillColor(NAVY)
    c.setFont("Helvetica-Bold", 8.5)
    c.drawString(22*mm, y-6*mm, title)
    c.setStrokeColor(LINE)
    yy = y-11*mm
    while yy > y-height+4*mm:
        c.line(22*mm, yy, W-22*mm, yy)
        yy -= 6*mm
    return y-height-4*mm

def matrix(y, headers, rows, widths=None, row_h=9*mm, font_size=6.8):
    x0 = 18*mm
    total = W-36*mm
    widths = widths or [total/len(headers)]*len(headers)
    c.setFillColor(NAVY)
    c.rect(x0, y-row_h, total, row_h, fill=1, stroke=0)
    x=x0
    for head,w in zip(headers,widths):
        c.setFillColor(white); c.setFont("Helvetica-Bold", font_size)
        c.drawCentredString(x+w/2, y-row_h+3.2*mm, head)
        x += w
    y -= row_h
    for idx,row in enumerate(rows):
        c.setFillColor(white if idx%2 else PALE)
        c.rect(x0, y-row_h, total, row_h, fill=1, stroke=0)
        x=x0
        for val,w in zip(row,widths):
            c.setStrokeColor(LINE); c.rect(x,y-row_h,w,row_h,fill=0,stroke=1)
            text(x+2*mm,y-3.5*mm,val,font_size,INK,width=w-4*mm,leading=7.2)
            x += w
        y -= row_h
    return y

def finish(page):
    footer(page)
    c.showPage()

# 1 cover
c.setFillColor(NAVY); c.rect(0,0,W,H,fill=1,stroke=0)
c.setFillColor(TEAL); c.circle(W-27*mm,H-25*mm,36*mm,fill=1,stroke=0)
c.setFillColor(CORAL); c.circle(W-12*mm,H-62*mm,20*mm,fill=1,stroke=0)
c.setFillColor(GOLD); c.roundRect(18*mm,H-55*mm,45*mm,9*mm,4*mm,fill=1,stroke=0)
c.setFillColor(NAVY); c.setFont("Helvetica-Bold",8); c.drawCentredString(40.5*mm,H-51.8*mm,"FIND MY TABLE")
c.setFillColor(white); c.setFont("Helvetica-Bold",35); c.drawString(18*mm,H-86*mm,"TABLE READY")
c.setFillColor(MINT); c.setFont("Helvetica-Bold",18); c.drawString(18*mm,H-99*mm,"Session Zero & Group")
c.drawString(18*mm,H-108*mm,"Compatibility Kit")
text(18*mm,H-127*mm,"Spot mismatches early. Build a table people can actually keep.",12,white,"Helvetica",W-52*mm,17)
c.setStrokeColor(TEAL); c.setLineWidth(2); c.line(18*mm,H-145*mm,W-50*mm,H-145*mm)
text(18*mm,H-156*mm,"SYSTEM-NEUTRAL",8,GOLD,"Helvetica-Bold")
text(18*mm,H-164*mm,"Print or type notes  •  30–45 minute guided conversation",9,white,width=W-40*mm)
c.setFillColor(CREAM); c.roundRect(18*mm,30*mm,W-36*mm,39*mm,4*mm,fill=1,stroke=0)
text(24*mm,58*mm,"FOR HOSTS FORMING A NEW OR MIXED GROUP",8,TEAL,"Helvetica-Bold")
text(24*mm,49*mm,"Compare schedule, commitment, play style, boundaries, access needs, and venue format — then make one clear decision before the campaign begins.",10,NAVY,"Helvetica-Bold",W-48*mm,14)
finish(1)

# 2 quick start
y=page_header("Start here","A good outcome includes “not this table.”","This kit is a decision aid, not a compatibility score. Use it before a campaign, recurring game night, or paid table.",2)
steps=[("1","Complete","Each person fills pages 3–9 privately or in quiet time."),("2","Compare","Share only what you choose. A boundary needs no explanation."),("3","Map","The host records alignment and mismatches on pages 10–11."),("4","Agree","Write specific owners, dates, and rules on page 12."),("5","Decide","Choose READY, READY WITH CHANGES, or NOT THIS TABLE."),("6","Review","Check after session one and after 30 days.")]
for n,t,b in steps:
    c.setFillColor(TEAL); c.circle(24*mm,y-2*mm,5*mm,fill=1,stroke=0)
    c.setFillColor(white); c.setFont("Helvetica-Bold",8); c.drawCentredString(24*mm,y-3.2*mm,n)
    c.setFillColor(NAVY); c.setFont("Helvetica-Bold",10); c.drawString(34*mm,y,t)
    y=text(34*mm,y-5*mm,b,8.5,INK,width=W-52*mm,leading=10)-4*mm
y=note_box(y,"GROUND RULES",36*mm,MINT)
text(23*mm,y+31*mm,"• Circumstances can change; update the agreement.\n• Do not pressure anyone to explain a boundary or access need.\n• One critical mismatch can matter more than ten matches.\n• “We’ll figure it out” is unresolved without an owner and date.",8.5,INK,width=W-46*mm,leading=12)
finish(2)

# 3 snapshot
y=page_header("Worksheet 1","My player snapshot","Complete this for yourself. Share only the parts needed to decide whether the table is workable.",3)
y=label_line(y,"Name or table name",1,"Pronouns optional")
y=label_line(y,"Preferred contact method",1)
y=check_row(y,["I confirm I meet the table’s stated age requirement","New to TTRPGs","Some experience","Very experienced"],2)
y=label_line(y,"Systems or genres I want to try",2)
y=label_line(y,"Systems, formats, or genres I do not want",2)
y=label_line(y,"Languages I can comfortably play in",1)
y=note_box(y,"A great session feels like…",23*mm)
y=note_box(y,"What usually makes me stop attending…",23*mm)
finish(3)

# 4 schedule
y=page_header("Worksheet 2","Schedule reality","Write the schedule you can keep, not the schedule you wish you could keep.",4)
y=label_line(y,"Timezone / usual location",1)
y=check_row(y,["Mon","Tue","Wed","Thu","Fri","Sat","Sun"],4)
y=label_line(y,"Earliest start / latest finish",1)
y=check_row(y,["Weekly","Every 2 weeks","Monthly","One-shot only","Flexible"],3)
y=label_line(y,"Preferred session length / earliest start date",1)
y=label_line(y,"Commitment window or expected end date",1)
y=label_line(y,"Known blackout dates / travel constraints",2)
y=label_line(y,"Minimum cancellation notice I can give",1)
y=label_line(y,"If I am late or absent, the group may…",2)
y=note_box(y,"My non-negotiable schedule constraint",20*mm,MINT)
finish(4)

# 5 format/access
y=page_header("Worksheet 3","Format, venue & access","A workable table includes the practical conditions people need to participate.",5)
y=check_row(y,["Online","Public venue","Private venue only by explicit agreement","Hybrid"],2)
y=label_line(y,"Travel radius / transport / parking",1)
y=label_line(y,"Platform, camera, microphone, text-chat, or caption needs",2)
y=label_line(y,"Seating, stairs, restroom, break, noise, light, or sensory needs",2)
y=label_line(y,"Food, allergy, service-animal, alcohol, or smoking considerations",2)
y=label_line(y,"Maximum spend per session, including venue/food",1)
y=check_row(y,["Share with full group","Share with host only","Ask me privately before sharing"],2)
y=note_box(y,"Host follow-up needed before I can commit",19*mm,MINT)
finish(5)

# 6 game promise
y=page_header("Worksheet 4","The game promise","The host completes this before asking players to commit.",6)
y=label_line(y,"System / campaign or one-shot / genre",1)
y=label_line(y,"Tone and content level in one sentence",2)
y=label_line(y,"Expected arc, session count, and ending condition",2)
y=label_line(y,"Character creation constraints / rules approach / homebrew",2)
y=label_line(y,"Failure, character loss, and difficulty expectations",2)
y=label_line(y,"Prep, homework, technology, or source ownership required",2)
y=check_row(y,["No recording","Private recording","Public stream/clips","AI-assisted material disclosed"],2)
y=label_line(y,"Price, payment timing, and refund rule — if any",2)
y=note_box(y,"Explicitly excluded from this game",18*mm,MINT)
finish(6)

# 7 compass
y=page_header("Worksheet 5","Play-style compass","Circle one number on each line. A difference is a discussion prompt, not a bad score.",7)
rows=[("Tactical challenge","1  2  3  4  5","Freeform story"),("Serious consequences","1  2  3  4  5","Light / casual"),("GM-led direction","1  2  3  4  5","Player-led exploration"),("Rules as written","1  2  3  4  5","Flexible rulings"),("Long character scenes","1  2  3  4  5","Fast scene changes"),("Shared spotlight","1  2  3  4  5","Competitive edge"),("Planned campaign","1  2  3  4  5","Improvised sandbox"),("High difficulty","1  2  3  4  5","Comfort-forward")]
y=matrix(y,["One end","Preference","Other end"],rows,[59*mm,55*mm,59*mm],10*mm,7.5)-5*mm
y=label_line(y,"My three must-haves",2)
y=label_line(y,"My three flex points",2)
y=note_box(y,"One play-style deal-breaker",18*mm,MINT)
finish(7)

# 8 commitment
y=page_header("Worksheet 6","Commitment & communication","Make reliability and conflict expectations visible before they become personal.",8)
y=label_line(y,"Arrival standard / cancellation notice / repeated no-show response",2)
y=label_line(y,"Between-game channel / response-time expectation",2)
y=label_line(y,"Who schedules / how the group makes decisions",2)
y=label_line(y,"How I prefer to receive feedback or resolve conflict",2)
y=check_row(y,["Devices okay","Devices for play only","Side chat okay","Guests by agreement","No photos","Photos by consent"],3)
y=label_line(y,"Payment deadline / refund rule / exit path — if applicable",2)
y=note_box(y,"The reliability promise I can honestly make",23*mm,MINT)
finish(8)

# 9 boundaries
y=page_header("Worksheet 7","Boundaries without interrogation","Mark privately. A person may change an answer at any time and never has to explain a boundary.",9)
headers=["Topic","OK","ASK","FADE","NO","PRIVATE"]
topics=["Graphic violence","Harm to children","Sexual content","Romance","Prejudice","Body horror","Illness / medical","Grief / death","Phobias","Loss of control","Player-v-player","Secrets / betrayal","Substance use","Religion / cults","Real-world politics","Other: _________"]
rows=[[t,"□","□","□","□","□"] for t in topics]
y=matrix(y,headers,rows,[60*mm,22.6*mm,22.6*mm,22.6*mm,22.6*mm,22.6*mm],7.2*mm,6.4)-3*mm
text(18*mm,y,"OK = okay to include  •  ASK = ask privately first  •  FADE = imply or skip detail  •  NO = do not include  •  PRIVATE = tell host only",7.2,MID,width=W-36*mm)
finish(9)

# 10 safety protocol
y=page_header("Worksheet 8","Pause & repair protocol","A worksheet reduces ambiguity; it cannot guarantee safety or replace qualified safeguarding.",10)
y=label_line(y,"Words or signals anyone may use to pause immediately",2)
y=label_line(y,"Private check-in method during play",2)
y=label_line(y,"When someone pauses, the table will…",3)
y=label_line(y,"Who follows up after a harmful or uncomfortable moment",1)
y=label_line(y,"What stays confidential / what may need escalation",2)
y=note_box(y,"Local, venue, platform, or professional rule that overrides this page",22*mm,MINT)
text(22*mm,y+17*mm,"If a credible safety concern appears, stop the activity and use the appropriate local, venue, platform, emergency, or professional process. Do not use this kit to investigate or adjudicate harm.",8,INK,width=W-44*mm,leading=10)
finish(10)

# 11 compatibility map
y=page_header("Group map","Compatibility at a glance","The host records the group pattern. “Workable” requires a specific change, owner, and date.",11)
areas=["Schedule","Frequency","Format / location","Cost","System / genre","Tone / content","Play style","Commitment","Communication","Boundaries","Accessibility","Recording / privacy"]
rows=[[a,"□","□","□","","" ] for a in areas]
y=matrix(y,["Area","Aligned","Change","Open","Owner","Due"],rows,[43*mm,23*mm,25*mm,22*mm,39*mm,21*mm],11.5*mm,6.6)-5*mm
y=note_box(y,"The one mismatch most likely to break this table",22*mm,MINT)
finish(11)

# 12 mismatch repair
y=page_header("Repair plan","Make the change concrete","Do not solve a boundary by asking the person with the boundary to absorb the cost.",12)
for idx in range(1,4):
    c.setFillColor(TEAL); c.setFont("Helvetica-Bold",9); c.drawString(18*mm,y,f"MISMATCH {idx}")
    y-=5*mm
    y=label_line(y,"What differs / why it matters",1)
    y=label_line(y,"Smallest change / owner / due date",1)
    y=label_line(y,"Trial period / success signal / fallback",1)
    y-=2*mm
y=check_row(y,["Voluntary","Specific","Reversible where possible","No explanation demanded","No one isolated","Real owner/resource"],3)
finish(12)

# 13 agreement
y=page_header("Shared record","Our table agreement","Keep only what the group agreed to share. Delete private working notes when they are no longer needed.",13)
fields=["Game promise","Schedule / location / platform","Attendance / cancellation","Communication / decisions","Rules / spotlight / devices","Pause / boundaries / access","Recording / privacy","Payment / refund — if any","Conflict / exit path","Review date"]
for field in fields:
    y=label_line(y,field,1)
text(18*mm,y+2*mm,"Participants acknowledge that this agreement is current, voluntary, and revisable. It is not a waiver of anyone’s rights or a guarantee of safety or attendance.",7.5,MID,width=W-36*mm,leading=9)
finish(13)

# 14 decision
y=page_header("Decision","Choose clearly","A respectful no is better than a campaign held together by unspoken assumptions.",14)
y=check_row(y,["READY — critical needs align","READY WITH CHANGES — conditions recorded","NOT THIS TABLE — close respectfully"],1,9)
y=label_line(y,"Decision reason / required changes",3)
y=label_line(y,"Next action / owner / date",2)
y=label_line(y,"Private confidence (0–10) / strongest reason",2)
y=label_line(y,"What experience or proof would change this decision",2)
y=check_row(y,["Check after session one","Check after 30 days","Check after material change"],3)
y=note_box(y,"Review notes",25*mm,MINT)
finish(14)

# 15 guide/license
y=page_header("Host guide","Facilitate; do not diagnose","Keep the conversation specific, private where needed, and easy to leave.",15)
cols=[("BEFORE","Send pages 3–10. Offer a private-response route. State exact format, cost, and limitations. Do not promise universal fit."),("DURING","Start with schedule and cost. Summarize rather than interpret. Separate preferences, needs, and hard conditions. Let anyone pass."),("CLOSE","Read the agreement. Ask private confidence. Name unresolved items. Make READY / CHANGES / NOT THIS TABLE explicit."),("AFTER","Share only the agreed record. Delete private notes. Review after the first session and 30 days. Record changes.")]
for head,body in cols:
    c.setFillColor(PALE); c.roundRect(18*mm,y-26*mm,W-36*mm,23*mm,3*mm,fill=1,stroke=0)
    c.setFillColor(TEAL); c.setFont("Helvetica-Bold",8); c.drawString(22*mm,y-9*mm,head)
    text(48*mm,y-9*mm,body,7.8,INK,width=W-70*mm,leading=9.5); y-=27*mm
c.setFillColor(NAVY); c.setFont("Helvetica-Bold",9); c.drawString(18*mm,y,"PERSONAL-USE LICENSE & LIMITS")
y=text(18*mm,y-6*mm,"Purchaser may print or digitally use copies for personal game groups. A paid GM/host may use it while facilitating their own tables. No resale, redistribution, public upload, sublicensing, template resale, or claiming authorship. Contact the seller for organizational or multi-host use.",7.7,INK,width=W-36*mm,leading=9.5)-2*mm
y=text(18*mm,y,"Independent, system-neutral product. Not affiliated with or endorsed by any game publisher, platform, venue, or trademark owner. No copied game rules or proprietary setting material is included.",7.7,INK,width=W-36*mm,leading=9.5)-2*mm
text(18*mm,y,"This kit cannot verify identity, prevent harm, replace professional safeguarding/accessibility/legal advice, guarantee compatibility, or ensure attendance. Use appropriate local guidance for minors, paid services, data collection, and safety. Version 1.0 — 2026-08-09.",7.7,INK,width=W-36*mm,leading=9.5)
finish(15)

c.save()
print(PDF)
