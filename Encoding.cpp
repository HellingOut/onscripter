/* -*- C++ -*-
 *
 *  Encoding.cpp - Character encoding handler
 *
 *  Copyright (c) 2019-2020 Ogapee. All rights reserved.
 *
 *  ogapee@aqua.dti2.ne.jp
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#include "Encoding.h"

extern unsigned short convSJIS2UTF16(unsigned short in);
extern unsigned short convUTF8ToUTF16(const char** src);

Encoding::Encoding()
{
    code = CODE_CP932;
}

Encoding::~Encoding()
{
}

void Encoding::setEncoding(int code)
{
    this->code = code;
}

static unsigned short convCP1251ToUTF16(unsigned char ch)
{
    static const unsigned short table[64] = {
        0x0402, 0x0403, 0x201a, 0x0453, 0x201e, 0x2026, 0x2020, 0x2021,
        0x20ac, 0x2030, 0x0409, 0x2039, 0x040a, 0x040c, 0x040b, 0x040f,
        0x0452, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014,
        0x0098, 0x2122, 0x0459, 0x203a, 0x045a, 0x045c, 0x045b, 0x045f,
        0x00a0, 0x040e, 0x045e, 0x0408, 0x00a4, 0x0490, 0x00a6, 0x00a7,
        0x0401, 0x00a9, 0x0404, 0x00ab, 0x00ac, 0x00ad, 0x00ae, 0x0407,
        0x00b0, 0x00b1, 0x0406, 0x0456, 0x0491, 0x00b5, 0x00b6, 0x00b7,
        0x0451, 0x2116, 0x0454, 0x00bb, 0x0458, 0x0405, 0x0455, 0x0457
    };

    if (ch < 0x80) return ch;
    if (ch >= 0xc0) return 0x0410 + (ch - 0xc0);
    return table[ch - 0x80];
}

int Encoding::getBytes(unsigned char ch, int code)
{
    if (code == -1) code = this->code;

    if (code == CODE_CP932) {
        if ((ch & 0xe0) == 0xe0 || (ch & 0xe0) == 0x80) return 2;
    }
    else if (code == CODE_CP1251) {
        return 1;
    }
    else {
        if (0 <= ch && ch < 0x80) return 1;
        if (0xc0 <= ch && ch < 0xe0) return 2;
        if (0xe0 <= ch && ch < 0xf0) return 3;
        if (0xf0 <= ch && ch < 0xf8) return 4;
    }

    return 1;
}

int Encoding::getNum(const unsigned char* buf)
{
    int n = 0;

    while (buf[0] != 0) {
        int n2 = getBytes(buf[0]);
        n++;
        if (n2 > 1) n++;
        buf += n2;
    }

    return n;
}

char Encoding::getTextMarker()
{
    if (code == CODE_UTF8)
        return '^';

    return '`';
}

unsigned short Encoding::getUTF16(const char* text, int code)
{
    unsigned short unicode = 0;

    if (code == -1) code = this->code;

    if (code == CODE_CP932) {
        if ((text[0] & 0xe0) == 0xe0 || (text[0] & 0xe0) == 0x80) {
            unsigned index = ((unsigned char*)text)[0];
            index = index << 8 | ((unsigned char*)text)[1];
            unicode = convSJIS2UTF16(index);
        }
        else {
            if ((text[0] & 0xe0) == 0xa0 || (text[0] & 0xe0) == 0xc0)
                unicode = ((unsigned char*)text)[0] - 0xa0 + 0xff60;
            else
                unicode = text[0];
        }
    }
    else if (code == CODE_CP1251) {
        unicode = convCP1251ToUTF16((unsigned char)text[0]);
    }
    else {
        unicode = convUTF8ToUTF16(&text);
    }

    return unicode;
}
