import { Alert } from '@mantine/core'
import { IconInfoCircle } from '@tabler/icons-react'
import type { ReactNode } from 'react'

// Marks a screen whose data is a hard-coded preview of the eventual feature.
function PreviewNote({ children }: { children: ReactNode }) {
  return (
    <Alert variant="light" icon={<IconInfoCircle size={18} />} title="Preview">
      {children}
    </Alert>
  )
}

export default PreviewNote
