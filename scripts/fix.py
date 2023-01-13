

import os
import re
directory = '/Users/icmccorm/Desktop/frerun/late'
extension = '.json'
for filename in os.listdir(directory):
    f = os.path.join(directory, filename)
    # checking if it is a file
    if os.path.isfile(f):
        m = re.search(r"-\d*\.\d*\.\d", filename)
        if(m is not None):
            start = m.span(0)[0]
            crate_name = filename[0:start]
            crate_version = filename[start + 1:-1*(len(extension))]
            os.rename(f, os.path.join(directory, f"{crate_name}{extension}"))
        else:
            print(f"ERR: {filename}")