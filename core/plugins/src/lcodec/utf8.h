/**
 * Copyright (C) 2008  Huang Guan
 * Copyright (C) 2011  iBoxpay.com inc.
 *
 * $Id: 509d9187fcedee642b722b528884dc8378b93ede $
 *
 * Description: GBK UTF-8 iconv functions header file
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#ifndef _UTF8_H
#define _UTF8_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * UTF-8 to GBK
 * @param src [in]
 * @param dst [out]
 * @param len [in] The most bytes which starting at dst, will be written.
 *
 */
void utf8_to_gb(const char* src, char* dst, int len);

/**
 * GBK to UTF-8
 *
 * @param src [in]
 * @param dst [out]
 * @param len [in] The most bytes which starting at dst, will be written.
 */
void gb_to_utf8(const char* src, char* dst, int len);

#ifdef __cplusplus
}
#endif

#endif  // end of _UTF8_H

