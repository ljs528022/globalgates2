package com.app.globalgates.service.video_chat;

import com.app.globalgates.aop.annotation.LogStatus;
import com.app.globalgates.aop.annotation.LogStatusWithReturn;
import com.app.globalgates.common.exception.SummationNotFoundException;
import com.app.globalgates.domain.video_chat.SummationVO;
import com.app.globalgates.dto.video_chat.SummationDTO;
import com.app.globalgates.repository.video_chat.SummationDAO;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;


@Service
@RequiredArgsConstructor
@Slf4j
public class SummationService {
    private final SummationDAO summationDAO;

    @Transactional
    @LogStatus
    public void save(SummationDTO summationDTO) {
        summationDAO.save(summationDTO.toVO());
    }

    @Transactional
    @Cacheable(value = "summation", key = "'id:' + #id")
    @LogStatusWithReturn
    public SummationDTO getSummation(Long id) {
        SummationVO summationVO = summationDAO.findById(id).orElseThrow(SummationNotFoundException::new);
        SummationDTO summationDTO = toDTO(summationVO);

        return summationDTO;
    }


    // toDTO
    public SummationDTO toDTO(SummationVO summationVO) {
        SummationDTO summationDTO = new SummationDTO();
        summationDTO.setId(summationVO.getId());
        summationDTO.setRecord_id(summationVO.getRecord_id());
        summationDTO.setText(summationVO.getText());

        return summationDTO;
    }

}
